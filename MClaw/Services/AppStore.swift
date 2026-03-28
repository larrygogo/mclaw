import Foundation
import SwiftData
import UIKit

private let avatars = ["star.fill", "building.columns", "laptopcomputer", "magnifyingglass", "map", "wrench.and.screwdriver", "lightbulb", "target", "flask", "safari"]
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
    private var modelContainer: ModelContainer?

    // MARK: - Init

    init(modelContainer: ModelContainer? = nil) {
        self.modelContainer = modelContainer
        loadGateways()
        gateway.onEvent { [weak self] event, payload in
            self?.handleEvent(event, payload: payload)
        }
    }

    // MARK: - SwiftData

    @MainActor
    func loadCachedMessages() {
        guard let container = modelContainer, !activeGatewayId.isEmpty else { return }
        let gwId = activeGatewayId
        let context = container.mainContext
        var descriptor = FetchDescriptor<PersistedMessage>(
            predicate: #Predicate { $0.gatewayId == gwId },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 2000
        guard let persisted = try? context.fetch(descriptor) else { return }
        messages = persisted.reversed().map { $0.toChatMessage() }
    }

    func getCacheSize() -> String {
        guard let container = modelContainer else { return "0" }
        let context = container.mainContext
        let count = (try? context.fetchCount(FetchDescriptor<PersistedMessage>())) ?? 0
        if count == 0 { return "无缓存" }
        // Estimate size from store file
        let config = ModelConfiguration("MClaw")
        let url = config.url
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let sizeMB = Double(fileSize) / 1_000_000
        if sizeMB >= 1 {
            return String(format: "%d 条 / %.1fMB", count, sizeMB)
        }
        return String(format: "%d 条 / %.0fKB", count, Double(fileSize) / 1000)
    }

    func clearCache() {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        do {
            try context.delete(model: PersistedMessage.self)
            try context.save()
        } catch {
            NSLog("[store] clearCache error: %@", "\(error)")
        }
        messages = []
        mountedCounts = [:]
        scrollPositions = [:]

        // Reset loading state so conversations re-fetch from server
        for i in conversations.indices {
            conversations[i].historyLoaded = false
            conversations[i].fullyLoaded = false
            conversations[i].loadedSessionCount = 0
            conversations[i].lastMessageText = ""
        }

        // Re-fetch from server
        if isConnected {
            let snapshot = conversations
            Task {
                for conv in snapshot {
                    await fetchAllSessions(for: conv)
                }
            }
        }
    }

    private func persistMessages(_ newMessages: [ChatMessage]) {
        guard let container = modelContainer, !newMessages.isEmpty, !activeGatewayId.isEmpty else { return }
        let gwId = activeGatewayId
        let context = ModelContext(container)
        context.autosaveEnabled = false
        for msg in newMessages {
            context.insert(PersistedMessage(from: msg, gatewayId: gwId))
        }
        try? context.save()
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

    func loadMockData() {
        isMockMode = true
        isConnected = true
        activeGatewayId = "mock"

        let mockAgents: [(String, String, String?, AgentStatus)] = [
            ("小南",     "star.fill",          "协调团队处理 PR #42",           .working),
            ("筑基",     "building.columns",    nil,                           .idle),
            ("码匠",     "laptopcomputer",      "实现看板拖拽功能...",           .working),
            ("探针",     "magnifyingglass",     "running integration tests",   .working),
            ("寻路",     "map",                 nil,                           .idle),
        ]

        agentList = mockAgents.enumerated().map { i, m in
            AgentInfo(id: "agent-\(i)", name: m.0, avatar: m.1, color: colors[i % colors.count])
        }

        for (i, m) in mockAgents.enumerated() {
            let id = "agent-\(i)"
            var state = AgentState(id: id, status: m.3)
            state.currentTask = m.2
            state.lastActivity = Date()
            agentStates[id] = state
        }

        let now = Date()

        // User conversations (我的)
        let sk0 = "agent:agent-0:main"
        let sk2 = "agent:agent-2:main"
        let sk3 = "agent:agent-3:main"

        // A2A conversations (员工)
        let a2a_02 = "agent:agent-2:subagent:aaa"
        let a2a_03 = "agent:agent-3:subagent:bbb"
        let a2a_04 = "agent:agent-4:subagent:ccc"

        conversations = [
            // 我的
            Conversation(id: "user:agent-0", sessionKey: sk0, sessionKeys: [sk0], agentId: "agent-0",
                         displayName: "小南", avatar: "star.fill", color: colors[0], kind: .user,
                         lastMessageText: "PR #42 已经审查完毕，修复建议已添加。",
                         lastTimestamp: now.addingTimeInterval(-120), historyLoaded: true),
            Conversation(id: "user:agent-2", sessionKey: sk2, sessionKeys: [sk2], agentId: "agent-2",
                         displayName: "码匠", avatar: "laptopcomputer", color: colors[2], kind: .user,
                         lastMessageText: "看板功能的前端已完成，等待 QA 验收。",
                         lastTimestamp: now.addingTimeInterval(-300), historyLoaded: true),
            Conversation(id: "user:agent-3", sessionKey: sk3, sessionKeys: [sk3], agentId: "agent-3",
                         displayName: "探针", avatar: "magnifyingglass", color: colors[3], kind: .user,
                         lastMessageText: "58/58 用例全部通过，无回归问题。",
                         lastTimestamp: now.addingTimeInterval(-600), historyLoaded: true),
            // 员工
            {
                var c = Conversation(id: "a2a:agent-0:agent-2", sessionKey: a2a_02, sessionKeys: [a2a_02], agentId: "agent-2",
                             displayName: "小南", avatar: "star.fill", color: colors[0], kind: .a2a,
                             lastMessageText: "feat/kanban 分支代码已提交。",
                             lastTimestamp: now.addingTimeInterval(-200), historyLoaded: true)
                c.secondaryName = "码匠"; c.secondaryAvatar = "laptopcomputer"
                return c
            }(),
            {
                var c = Conversation(id: "a2a:agent-0:agent-3", sessionKey: a2a_03, sessionKeys: [a2a_03], agentId: "agent-3",
                             displayName: "小南", avatar: "star.fill", color: colors[0], kind: .a2a,
                             lastMessageText: "集成测试已全部通过。",
                             lastTimestamp: now.addingTimeInterval(-500), historyLoaded: true)
                c.secondaryName = "探针"; c.secondaryAvatar = "magnifyingglass"
                return c
            }(),
            {
                var c = Conversation(id: "a2a:agent-0:agent-4", sessionKey: a2a_04, sessionKeys: [a2a_04], agentId: "agent-4",
                             displayName: "小南", avatar: "star.fill", color: colors[0], kind: .a2a,
                             lastMessageText: "相关文档和 API 参考已整理完毕。",
                             lastTimestamp: now.addingTimeInterval(-900), historyLoaded: true)
                c.secondaryName = "寻路"; c.secondaryAvatar = "map"
                return c
            }(),
        ]

        // Generate 1000 messages for 小南 conversation to test lazy loading
        let userTexts = [
            "这个怎么处理？", "进展如何？", "好的", "帮我看一下", "部署了吗",
            "测试通过了吗", "有什么问题吗", "继续", "改一下这里", "收到",
            "再确认一下", "优先级调高", "文档更新了吗", "合并吧", "下一步做什么",
        ]
        let agentTexts = [
            "收到，正在处理中...",
            "已完成。共修改 3 个文件，新增 128 行代码。",
            "发现一个潜在问题：`UserService.login()` 缺少并发锁，建议加 `@MainActor`。",
            "已部署到 staging 环境，地址：`https://staging.example.com`",
            "测试通过 ✅ 58/58 用例，0 失败，覆盖率 87%。",
            "已合并到 main 分支，CI 流水线运行中。",
            "代码审查完毕，LGTM。建议补充边界条件的单测。",
            "数据库迁移脚本已生成：`migrations/20260328_add_kanban.sql`",
            "性能测试结果：P99 延迟从 320ms 降到 85ms，提升 73%。",
            "依赖更新：升级 `swift-nio` 到 2.65.0，修复内存泄漏。",
            "文档已同步到 Notion，看板需求页面已更新。",
            "发现 iOS 端 WebSocket 重连逻辑有 bug，已修复并提 PR。",
            "缓存命中率从 62% 提升到 91%，减少 DB 查询 3200 次/分钟。",
            "安全扫描完成，未发现高危漏洞。2 个中危已修复。",
            "API 限流策略已上线：每用户 100 req/min，超限返回 429。",
        ]

        var allMessages: [ChatMessage] = []

        for i in 0..<1000 {
            let isUser = i % 3 == 0
            let t = now.addingTimeInterval(Double(-100000 + i * 100))
            allMessages.append(ChatMessage(
                id: "bulk-\(i)",
                sessionKey: sk0,
                agentId: "agent-0",
                role: isUser ? .user : .agent,
                text: isUser ? userTexts[i % userTexts.count] : agentTexts[i % agentTexts.count],
                timestamp: t,
                runId: nil
            ))
        }

        // Add messages with images
        func mockImage(color: UIColor, size: CGSize = CGSize(width: 300, height: 200), text: String = "") -> Data {
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.jpegData(withCompressionQuality: 0.8) { ctx in
                color.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                if !text.isEmpty {
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 24),
                        .foregroundColor: UIColor.white
                    ]
                    let str = text as NSString
                    let textSize = str.size(withAttributes: attrs)
                    str.draw(at: CGPoint(x: (size.width - textSize.width) / 2,
                                         y: (size.height - textSize.height) / 2), withAttributes: attrs)
                }
            }
        }

        // User sends a screenshot
        var imgMsg1 = ChatMessage(id: "img-1", sessionKey: sk0, agentId: "agent-0", role: .user,
                    text: "看看这个设计稿", timestamp: now.addingTimeInterval(-500), runId: nil)
        imgMsg1.localImageData = mockImage(color: .systemBlue, size: CGSize(width: 400, height: 300), text: "设计稿 v2")
        allMessages.append(imgMsg1)

        allMessages.append(ChatMessage(id: "img-1-reply", sessionKey: sk0, agentId: "agent-0", role: .agent,
                    text: "收到设计稿。整体布局很清晰，配色方案不错。建议导航栏高度从 64pt 调整到 44pt，更符合 iOS 规范。",
                    timestamp: now.addingTimeInterval(-480), runId: nil))

        // User sends another image
        var imgMsg2 = ChatMessage(id: "img-2", sessionKey: sk0, agentId: "agent-0", role: .user,
                    text: "", timestamp: now.addingTimeInterval(-300), runId: nil)
        imgMsg2.localImageData = mockImage(color: .systemGreen, size: CGSize(width: 300, height: 400), text: "截图")
        allMessages.append(imgMsg2)

        allMessages.append(ChatMessage(id: "img-2-reply", sessionKey: sk0, agentId: "agent-0", role: .agent,
                    text: "这是测试环境的截图吧？看起来 UI 渲染正常，数据也加载出来了。",
                    timestamp: now.addingTimeInterval(-280), runId: nil))

        // Agent sends an image (with text)
        var imgMsg3 = ChatMessage(id: "img-3", sessionKey: sk0, agentId: "agent-0", role: .agent,
                    text: "这是修改后的效果", timestamp: now.addingTimeInterval(-200), runId: nil)
        imgMsg3.localImageData = mockImage(color: .systemOrange, size: CGSize(width: 350, height: 250), text: "After")
        allMessages.append(imgMsg3)

        //码匠 conversation with image
        var imgMsg4 = ChatMessage(id: "img-4", sessionKey: sk2, agentId: "agent-2", role: .agent,
                    text: "看板页面完成了", timestamp: now.addingTimeInterval(-250), runId: nil)
        imgMsg4.localImageData = mockImage(color: .systemPurple, size: CGSize(width: 400, height: 500), text: "Kanban Board")
        allMessages.append(imgMsg4)

        // Add other conversations' messages
        allMessages += [
            ChatMessage(id: "m11", sessionKey: sk2, agentId: "agent-2", role: .user,
                        text: "看板功能的需求文档在 shared/design-kanban.md", timestamp: now.addingTimeInterval(-2000), runId: nil),
            ChatMessage(id: "m12", sessionKey: sk2, agentId: "agent-2", role: .agent,
                        text: "收到，已阅读需求文档。计划分三步实现：\n1. 后端 API（GET/PATCH）\n2. 前端三列看板 + 拖拽\n3. 实时轮询同步\n\n预计 30 分钟完成。",
                        timestamp: now.addingTimeInterval(-1900), runId: nil),
            ChatMessage(id: "m13", sessionKey: sk2, agentId: "agent-2", role: .user,
                        text: "走 feat/kanban 分支", timestamp: now.addingTimeInterval(-1800), runId: nil),
            ChatMessage(id: "m14", sessionKey: sk2, agentId: "agent-2", role: .agent,
                        text: "看板功能的前端已完成，等待 QA 验收。\n\n提交了 12 个文件，修改 3 个，共 1229 行代码。",
                        timestamp: now.addingTimeInterval(-300), runId: nil),
            ChatMessage(id: "m15", sessionKey: sk3, agentId: "agent-3", role: .user,
                        text: "跑一下看板功能的集成测试", timestamp: now.addingTimeInterval(-1200), runId: nil),
            ChatMessage(id: "m16", sessionKey: sk3, agentId: "agent-3", role: .agent,
                        text: "58/58 用例全部通过，无回归问题。", timestamp: now.addingTimeInterval(-600), runId: nil),
            // A2A
            ChatMessage(id: "a01", sessionKey: a2a_02, agentId: "agent-2", role: .user,
                        text: "请按照 shared/design-kanban.md 实现看板功能", timestamp: now.addingTimeInterval(-2000), runId: nil),
            ChatMessage(id: "a02", sessionKey: a2a_02, agentId: "agent-2", role: .agent,
                        text: "feat/kanban 分支代码已提交。新增 12 个文件，共 1229 行代码。",
                        timestamp: now.addingTimeInterval(-200), runId: nil),
            ChatMessage(id: "a03", sessionKey: a2a_03, agentId: "agent-3", role: .user,
                        text: "对 feat/kanban 分支执行集成测试", timestamp: now.addingTimeInterval(-1000), runId: nil),
            ChatMessage(id: "a04", sessionKey: a2a_03, agentId: "agent-3", role: .agent,
                        text: "集成测试已全部通过。58/58 用例，0 失败。", timestamp: now.addingTimeInterval(-500), runId: nil),
            ChatMessage(id: "a05", sessionKey: a2a_04, agentId: "agent-4", role: .user,
                        text: "调研主流看板系统的 API 设计", timestamp: now.addingTimeInterval(-3000), runId: nil),
            ChatMessage(id: "a06", sessionKey: a2a_04, agentId: "agent-4", role: .agent,
                        text: "相关文档和 API 参考已整理完毕，输出到 shared/research-kanban-api.md。",
                        timestamp: now.addingTimeInterval(-900), runId: nil),
        ]

        messages = allMessages

        if gateways.isEmpty {
            gateways = [GatewayConfig(id: "mock", name: "Demo Gateway", url: "ws://localhost:8080", token: "")]
        }
    }
}
