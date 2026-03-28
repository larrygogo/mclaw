import Foundation
import SwiftData
import UIKit

private let avatars = MockDataProvider.avatars
private let colors = Theme.agentColors

private let gatewaysKey = "mclaw-gateways"
private let activeGatewayKey = "mclaw-active-gateway"

@Observable
final class AppStore {

    // MARK: - State

    var gateways: [GatewayConfig] = []
    var activeGatewayId: String = ""

    var isMockMode = false
    var isConnected = false
    var isConnecting = false
    var connectionError: String?
    var isPairingRequired = false
    var pairingDeviceId: String?
    var pairingRequestId: String?

    var agentList: [AgentInfo] = []
    var agentStates: [String: AgentState] = [:]
    var messages: [ChatMessage] = []
    var conversations: [Conversation] = []
    var mountedCounts: [String: Int] = [:]      // conversationId → number of messages mounted
    var scrollPositions: [String: String] = [:]  // conversationId → message ID at scroll position

    let gateway = GatewayClient()
    let persistence: PersistenceService

    // MARK: - Init

    init(modelContainer: ModelContainer? = nil) {
        self.persistence = PersistenceService(modelContainer: modelContainer)
        loadGateways()
        gateway.onEvent { [weak self] event, payload in
            self?.handleEvent(event, payload: payload)
        }
    }

    // MARK: - Cache

    @MainActor
    func loadCachedMessages() {
        messages = persistence.loadCachedMessages(gatewayId: activeGatewayId)
    }

    func getCacheSize() -> String { persistence.getCacheSize() }

    func clearCache() {
        persistence.clearPersistedMessages()
        messages = []
        mountedCounts = [:]
        scrollPositions = [:]

        for i in conversations.indices {
            conversations[i].historyLoaded = false
            conversations[i].fullyLoaded = false
            conversations[i].loadedSessionCount = 0
            conversations[i].lastMessageText = ""
        }

        if isConnected {
            let snapshot = conversations
            Task {
                for conv in snapshot {
                    await fetchAllSessions(for: conv)
                }
            }
        }
    }

    func persistMessages(_ newMessages: [ChatMessage]) {
        persistence.persistMessages(newMessages, gatewayId: activeGatewayId)
    }

    // MARK: - Gateway config persistence

    func loadGateways() {
        if let data = UserDefaults.standard.data(forKey: gatewaysKey),
           let list = try? JSONDecoder().decode([GatewayConfig].self, from: data) {
            gateways = list
        }
        activeGatewayId = UserDefaults.standard.string(forKey: activeGatewayKey) ?? ""
    }

    func saveGateways() {
        if let data = try? JSONEncoder().encode(gateways) {
            UserDefaults.standard.set(data, forKey: gatewaysKey)
        }
    }

    func addGateway(_ config: GatewayConfig) {
        gateways.append(config)
        saveGateways()
    }

    func deleteGateway(id: String) {
        gateways.removeAll { $0.id == id }
        saveGateways()
        if activeGatewayId == id {
            activeGatewayId = ""
            UserDefaults.standard.removeObject(forKey: activeGatewayKey)
        }
    }

    // MARK: - Connect

    func connect(to config: GatewayConfig) async {
        isConnecting = true
        connectionError = nil

        // Precheck: test connection with a temporary client before dropping the current one
        let probe = GatewayClient()
        do {
            try await probe.connect(url: config.url, token: config.token)
            probe.disconnect()
        } catch {
            probe.disconnect()
            isConnecting = false
            if let gwErr = error as? GatewayClientError, case .pairingRequired(let deviceId, let requestId) = gwErr {
                isPairingRequired = true
                pairingDeviceId = deviceId
                pairingRequestId = requestId
                connectionError = nil
            } else {
                connectionError = error.localizedDescription
            }
            return
        }

        // Precheck passed — now do the real switch
        gateway.disconnect()
        isConnected = false
        agentList = []
        agentStates = [:]
        messages = []
        conversations = []
        mountedCounts = [:]
        scrollPositions = [:]

        do {
            try await gateway.connect(url: config.url, token: config.token)
            isPairingRequired = false
            pairingDeviceId = nil
            let raw = try await gateway.listAgents()
            agentList = buildAgentList(raw)
            for agent in agentList {
                agentStates[agent.id] = AgentState(id: agent.id, status: .idle)
            }
            isConnected = true

            if let result = try? await gateway.listSessions(limit: 1000),
               let sessions = result["sessions"] as? [[String: Any]] {

                // Group sessions: user by agentId, A2A by agent pair
                struct GroupInfo {
                    let agent: AgentInfo
                    var keys: [String]
                    var latestUpdatedAt: Date
                }
                struct A2AGroupInfo {
                    let parentAgent: AgentInfo
                    let childAgent: AgentInfo
                    var keys: [String]
                    var latestUpdatedAt: Date
                }
                var userGroups: [String: GroupInfo] = [:]
                var a2aGroups: [String: A2AGroupInfo] = [:]

                for session in sessions {
                    guard let key = session["key"] as? String else { continue }

                    // Heartbeat filter
                    let displayName = session["displayName"] as? String ?? ""
                    let lastTo = session["lastTo"] as? String ?? ""
                    let deliveryTo = (session["deliveryContext"] as? [String: Any])?["to"] as? String ?? ""
                    let originProvider = (session["origin"] as? [String: Any])?["provider"] as? String ?? ""
                    if displayName == "heartbeat" || lastTo == "heartbeat"
                        || deliveryTo == "heartbeat" || originProvider == "heartbeat" { continue }

                    guard let agentId = agentIdFromSessionKey(key),
                          let agentInfo = agentList.first(where: { $0.id == agentId }) else { continue }

                    let updatedAt = (session["updatedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantPast
                    let isA2A = key.contains(":subagent:")

                    if isA2A {
                        let parentKey = session["spawnedBy"] as? String ?? session["parentSessionKey"] as? String ?? ""
                        let parentAgentId = agentIdFromSessionKey(parentKey) ?? "main"
                        let parentAgent = agentList.first(where: { $0.id == parentAgentId }) ?? agentInfo
                        let pairKey = [parentAgentId, agentId].sorted().joined(separator: ":")
                        if a2aGroups[pairKey] != nil {
                            a2aGroups[pairKey]!.keys.append(key)
                            if updatedAt > a2aGroups[pairKey]!.latestUpdatedAt {
                                a2aGroups[pairKey]!.latestUpdatedAt = updatedAt
                            }
                        } else {
                            a2aGroups[pairKey] = A2AGroupInfo(parentAgent: parentAgent, childAgent: agentInfo, keys: [key], latestUpdatedAt: updatedAt)
                        }
                    } else {
                        if userGroups[agentId] != nil {
                            userGroups[agentId]!.keys.append(key)
                            if updatedAt > userGroups[agentId]!.latestUpdatedAt {
                                userGroups[agentId]!.latestUpdatedAt = updatedAt
                            }
                        } else {
                            userGroups[agentId] = GroupInfo(agent: agentInfo, keys: [key], latestUpdatedAt: updatedAt)
                        }
                    }
                }

                // Create one Conversation per user agent
                for (agentId, group) in userGroups {
                    var conv = Conversation(
                        id: "user:\(agentId)",
                        sessionKey: group.keys.first ?? "",
                        sessionKeys: group.keys,
                        agentId: agentId,
                        displayName: group.agent.name,
                        avatar: group.agent.avatar,
                        color: group.agent.color,
                        kind: .user
                    )
                    conv.lastTimestamp = group.latestUpdatedAt
                    conversations.append(conv)
                }

                // Create one Conversation per A2A agent pair
                for (pairKey, group) in a2aGroups {
                    var conv = Conversation(
                        id: "a2a:\(pairKey)",
                        sessionKey: group.keys.first ?? "",
                        sessionKeys: group.keys,
                        agentId: group.childAgent.id,
                        displayName: group.parentAgent.name,
                        avatar: group.parentAgent.avatar,
                        color: group.parentAgent.color,
                        kind: .a2a
                    )
                    conv.secondaryAgentId = group.childAgent.id
                    conv.secondaryName = group.childAgent.name
                    conv.secondaryAvatar = group.childAgent.avatar
                    conv.lastTimestamp = group.latestUpdatedAt
                    conversations.append(conv)
                }

            }

            activeGatewayId = config.id
            UserDefaults.standard.set(config.id, forKey: activeGatewayKey)

            // Load cached messages for this gateway and update previews
            loadCachedMessages()
            updateConversationPreviews()

            // Background: fetch new messages from server
            let snapshot = conversations
            Task {
                for conv in snapshot {
                    await fetchAllSessions(for: conv)
                }
            }
        } catch GatewayClientError.pairingRequired(let deviceId, let requestId) {
            isPairingRequired = true
            pairingDeviceId = deviceId
            pairingRequestId = requestId
            connectionError = nil
            isConnected = false
        } catch {
            connectionError = error.localizedDescription
            isPairingRequired = false
            isConnected = false
        }

        isConnecting = false
    }

    // MARK: - Fetch (background network loading into cache)

    /// Fetch all sessions for a conversation into cache
    func fetchAllSessions(for conversation: Conversation) async {
        let keys = conversation.allSessionKeys
        let startIndex = conversation.loadedSessionCount
        for index in startIndex..<keys.count {
            let key = keys[index]
            let agentId = agentIdFromSessionKey(key) ?? conversation.agentId
            if let hist = try? await gateway.chatHistory(sessionKey: key, limit: 100) {
                parseHistory(hist, sessionKey: key, agentId: agentId)
            }
            if let i = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[i].loadedSessionCount = index + 1
                if !conversations[i].historyLoaded { conversations[i].historyLoaded = true }
                if index + 1 >= keys.count { conversations[i].fullyLoaded = true }
            }
        }
        updateConversationPreviews()
    }

    /// Fetch just the next unloaded session
    private func fetchNextSession(for conversation: Conversation) async {
        guard !conversation.fullyLoaded else { return }
        let keys = conversation.allSessionKeys
        let nextIndex = conversation.loadedSessionCount
        guard nextIndex < keys.count else {
            if let i = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[i].fullyLoaded = true
            }
            return
        }
        let key = keys[nextIndex]
        let agentId = agentIdFromSessionKey(key) ?? conversation.agentId
        if let hist = try? await gateway.chatHistory(sessionKey: key, limit: 100) {
            parseHistory(hist, sessionKey: key, agentId: agentId)
        }
        if let i = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[i].loadedSessionCount = nextIndex + 1
            if nextIndex + 1 >= keys.count { conversations[i].fullyLoaded = true }
        }
        updateConversationPreviews()
    }

    func disconnect() {
        gateway.disconnect()
        isConnected = false
        agentList = []
        agentStates = [:]
        messages = []
        conversations = []
        activeGatewayId = ""
        UserDefaults.standard.removeObject(forKey: activeGatewayKey)
    }

    // MARK: - Messaging

    func sendMessage(sessionKey: String, agentId: String, text: String, imageData: Data? = nil) async {
        var msg = ChatMessage(
            id: "local-\(Date().timeIntervalSince1970)",
            sessionKey: sessionKey,
            agentId: agentId,
            role: .user,
            text: text.isEmpty && imageData != nil ? "" : text,
            timestamp: Date(),
            runId: nil
        )
        msg.localImageData = imageData
        addMessage(msg)
        updateAgent(agentId, status: .working, task: String(text.prefix(80)))

        if isMockMode {
            mockAgentReply(sessionKey: sessionKey, agentId: agentId, userText: text)
            return
        }

        do {
            var attachments: [[String: Any]]?
            if let imageData {
                attachments = [[
                    "type": "image",
                    "mimeType": "image/jpeg",
                    "content": imageData.base64EncodedString()
                ]]
            }
            let msg = text.isEmpty ? "请看图片" : text
            NSLog("[store] sendChat sessionKey=%@ msg=%@ hasAttachments=%d", sessionKey, msg, attachments != nil ? 1 : 0)
            try await gateway.sendChat(sessionKey: sessionKey, message: msg, attachments: attachments)
            NSLog("[store] sendChat success")
        } catch {
            NSLog("[store] sendChat error: %@", "\(error)")
        }
    }

    private func mockAgentReply(sessionKey: String, agentId: String, userText: String) {
        let agentName = agentList.first(where: { $0.id == agentId })?.name ?? "Agent"

        // Simulate streaming after 0.5s
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            updateAgent(agentId, status: .working, streaming: .some("思考中..."))

            try? await Task.sleep(for: .seconds(1.0))
            let reply = "收到「\(userText)」。\(agentName)已处理完毕，一切正常。"
            updateAgent(agentId, status: .working, streaming: .some(reply))

            try? await Task.sleep(for: .seconds(1.0))
            updateAgent(agentId, status: .idle, streaming: .some(nil))

            addMessage(ChatMessage(
                id: "mock-reply-\(Date().timeIntervalSince1970)",
                sessionKey: sessionKey,
                agentId: agentId,
                role: .agent,
                text: reply,
                timestamp: Date(),
                runId: nil
            ))
        }
    }

    // MARK: - Query helpers

    // MARK: - Mount (display window from local cache)

    /// Returns the last N messages for display (mounted window)
    func mountedMessages(for conversation: Conversation) -> [ChatMessage] {
        let keys = Set(conversation.allSessionKeys)
        let all = messages.filter { keys.contains($0.sessionKey) }
                          .sorted { $0.timestamp < $1.timestamp }
        let count = mountedCounts[conversation.id] ?? 30
        if all.count <= count { return all }
        return Array(all.suffix(count))
    }

    /// Expand the mounted window — instant, no network call
    func mountMore(for conversation: Conversation) {
        let keys = Set(conversation.allSessionKeys)
        let totalAvailable = messages.filter { keys.contains($0.sessionKey) }.count
        let current = mountedCounts[conversation.id] ?? 30
        mountedCounts[conversation.id] = current + 30

        if current + 30 >= totalAvailable, !conversation.fullyLoaded {
            Task { await fetchNextSession(for: conversation) }
        }
        updateConversationPreviews()
    }

    /// Whether all cached messages are mounted AND all sessions fetched
    func isFullyMounted(for conversation: Conversation) -> Bool {
        let keys = Set(conversation.allSessionKeys)
        let total = messages.filter { keys.contains($0.sessionKey) }.count
        let mounted = mountedCounts[conversation.id] ?? 30
        return mounted >= total && conversation.fullyLoaded
    }

    // MARK: - Private helpers

    private func addMessage(_ msg: ChatMessage) {
        // Dedup by ID or by content (same session + role + text within 5s window)
        guard !messages.contains(where: {
            $0.id == msg.id ||
            ($0.sessionKey == msg.sessionKey && $0.role == msg.role && $0.text == msg.text
             && abs($0.timestamp.timeIntervalSince(msg.timestamp)) < 5)
        }) else { return }
        messages.append(msg)
        if messages.count > 2000 {
            messages.removeFirst(messages.count - 2000)
        }
        persistMessages([msg])
        updateConversationPreviews()
    }

    private func updateConversationPreview(for msg: ChatMessage) {
        guard let i = conversations.firstIndex(where: { $0.allSessionKeys.contains(msg.sessionKey) }) else { return }
        if msg.timestamp >= conversations[i].lastTimestamp {
            let preview = msg.localImageData != nil ? "[图片]" : String(msg.text.prefix(60))
            conversations[i].lastMessageText = preview
            conversations[i].lastTimestamp = msg.timestamp
        }
    }

    func updateConversationPreviews() {
        for i in conversations.indices {
            let keys = Set(conversations[i].allSessionKeys)
            if let last = messages.filter({ keys.contains($0.sessionKey) }).max(by: { $0.timestamp < $1.timestamp }) {
                let preview = last.localImageData != nil ? "[图片]" : String(last.text.prefix(60))
                conversations[i].lastMessageText = preview
                conversations[i].lastTimestamp = last.timestamp
            }
        }
    }

    private enum OptionalValue<T> {
        case none, some(T?)
    }
    private func updateAgent(_ id: String, status: AgentStatus? = nil,
                              task: String? = nil, streaming: OptionalValue<String> = .none) {
        var state = agentStates[id] ?? AgentState(id: id)
        if let s = status { state.status = s }
        if let t = task { state.currentTask = t }
        if case .some(let v) = streaming { state.streamingText = v }
        state.lastActivity = Date()
        agentStates[id] = state
    }

    private func handleEvent(_ event: String, payload: [String: Any]) {
        switch event {
        case "agent":
            handleAgentEvent(payload)
        case "chat":
            handleChatEvent(payload)
        case "presence", "agent.status":
            if let agentId = payload["agentId"] as? String,
               let statusStr = payload["status"] as? String,
               let status = AgentStatus(rawValue: statusStr) {
                updateAgent(agentId, status: status, task: payload["task"] as? String)
            }
        default:
            break
        }
    }

    private func handleAgentEvent(_ payload: [String: Any]) {
        guard let sessionKey = payload["sessionKey"] as? String,
              let agentId = agentIdFromSessionKey(sessionKey),
              let stream = payload["stream"] as? String else { return }

        let data = payload["data"] as? [String: Any]
        let runId = payload["runId"] as? String

        if stream == "lifecycle", let data {
            switch data["phase"] as? String {
            case "start":
                updateAgent(agentId, status: .working, streaming: .some(""))
            case "end":
                updateAgent(agentId, status: .idle, streaming: .some(nil))
                // Don't add message here — let chat.final handle it to avoid duplicates
                if let runId { runTexts.removeValue(forKey: runId) }
            default:
                break
            }
        }

        if stream == "assistant", let data, let runId, let text = data["text"] as? String, !text.isEmpty {
            runTexts[runId] = text
            updateAgent(agentId, status: .working, task: String(text.prefix(80)), streaming: .some(text))
        }
    }

    private func handleChatEvent(_ payload: [String: Any]) {
        guard payload["state"] as? String == "final",
              let sessionKey = payload["sessionKey"] as? String,
              let agentId = agentIdFromSessionKey(sessionKey),
              let message = payload["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return }

        let runId = payload["runId"] as? String
        if let runId { runTexts.removeValue(forKey: runId) }

        updateAgent(agentId, status: .idle, streaming: .some(nil))

        let role = message["role"] as? String
        let ts = (message["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()

        let text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")

        guard !text.isEmpty else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("HEARTBEAT") else { return }
        if message["provenance"] != nil { return }

        // Use __openclaw.id if available (matches history), fall back to runId
        let openclawId = (message["__openclaw"] as? [String: Any])?["id"] as? String
        let msgId = openclawId ?? runId ?? "chat-\(sessionKey)-\(Int(ts.timeIntervalSince1970 * 1000))"

        addMessage(ChatMessage(
            id: msgId,
            sessionKey: sessionKey,
            agentId: agentId,
            role: role == "assistant" ? .agent : .user,
            text: text,
            timestamp: ts,
            runId: runId
        ))
    }

    private func parseHistory(_ hist: [String: Any], sessionKey: String, agentId: String) {
        guard let msgs = hist["messages"] as? [[String: Any]] else { return }
        var newMessages: [ChatMessage] = []

        for m in msgs {
            let role = m["role"] as? String
            guard role == "user" || role == "assistant" else { continue }
            let ts = (m["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
            let content = m["content"] as? [[String: Any]] ?? []
            let textParts = content
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
            // Check for omitted images
            let hasImage = content.contains { $0["type"] as? String == "image" }
            let imageInfo = content.first(where: { $0["type"] as? String == "image" })
            let isOmitted = imageInfo?["omitted"] as? Bool == true
            let imageBytes = imageInfo?["bytes"] as? Int

            var text = textParts.joined(separator: "\n")
            if hasImage && isOmitted {
                let sizeStr = imageBytes.map { "\(String(format: "%.1f", Double($0) / 1_000_000))MB" } ?? ""
                let label = "[图片 \(sizeStr)]"
                text = text.isEmpty ? label : "\(text)\n\(label)"
            }
            guard !text.isEmpty else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Filter heartbeat messages by content
            guard !trimmed.contains("HEARTBEAT") else { continue }
            // Filter system-generated messages (subagent results injected as "user" role)
            if m["provenance"] != nil { continue }

            let openclaw = m["__openclaw"] as? [String: Any]
            let msgId = openclaw?["id"] as? String
                ?? "hist-\(sessionKey)-\(openclaw?["seq"] as? Int ?? Int(ts.timeIntervalSince1970))-\(role ?? "x")"

            let msgRole: MessageRole = role == "assistant" ? .agent : .user
            // Live dedup: check current messages array (not a snapshot)
            let isDuplicate = messages.contains(where: {
                $0.id == msgId ||
                ($0.sessionKey == sessionKey && $0.role == msgRole && $0.text == text
                 && abs($0.timestamp.timeIntervalSince(ts)) < 5)
            })
            guard !isDuplicate else { continue }
            // Also check within this batch
            guard !newMessages.contains(where: {
                $0.id == msgId ||
                ($0.sessionKey == sessionKey && $0.role == msgRole && $0.text == text
                 && abs($0.timestamp.timeIntervalSince(ts)) < 5)
            }) else { continue }

            newMessages.append(ChatMessage(
                id: msgId,
                sessionKey: sessionKey,
                agentId: agentId,
                role: role == "assistant" ? .agent : .user,
                text: text,
                timestamp: ts,
                runId: nil
            ))
        }

        // Batch append — single SwiftUI update
        if !newMessages.isEmpty {
            messages.append(contentsOf: newMessages)
            if messages.count > 2000 {
                messages.removeFirst(messages.count - 2000)
            }
            if let latest = newMessages.max(by: { $0.timestamp < $1.timestamp }) {
                updateConversationPreview(for: latest)
            }
            persistMessages(newMessages)
        }
    }

    private var runTexts: [String: String] = [:]

    private func agentIdFromSessionKey(_ key: String) -> String? {
        let parts = key.split(separator: ":")
        return parts.count >= 2 ? String(parts[1]) : nil
    }


    private func buildAgentList(_ raw: [[String: Any]]) -> [AgentInfo] {
        return raw.enumerated().map { i, a in
            let id = a["agentId"] as? String ?? a["id"] as? String ?? UUID().uuidString
            let serverAvatar = a["avatar"] as? String ?? a["emoji"] as? String ?? a["icon"] as? String ?? ""
            let avatar = serverAvatar.isEmpty ? avatars[i % avatars.count] : serverAvatar
            let serverColor = a["color"] as? String ?? ""
            let color = serverColor.isEmpty ? colors[i % colors.count] : serverColor
            return AgentInfo(
                id: id,
                name: a["name"] as? String ?? "Agent",
                avatar: avatar,
                color: color
            )
        }
    }

    // MARK: - Mock Data

    func loadMockData() { MockDataProvider.load(into: self) }
}
