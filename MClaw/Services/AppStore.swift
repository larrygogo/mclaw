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
    var mountedCounts: [String: Int] = [:]
    var scrollPositions: [String: String] = [:]

    let gateway = GatewayClient()
    let persistence: PersistenceService
    private(set) var messageService: MessageService!

    // MARK: - Init

    init(modelContainer: ModelContainer? = nil) {
        self.persistence = PersistenceService(modelContainer: modelContainer)
        loadGateways()
        self.messageService = MessageService(store: self)
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

    // MARK: - Delegated to MessageService

    func mountedMessages(for conversation: Conversation) -> [ChatMessage] {
        messageService.mountedMessages(for: conversation)
    }

    func mountMore(for conversation: Conversation) {
        messageService.mountMore(for: conversation)
    }

    func isFullyMounted(for conversation: Conversation) -> Bool {
        messageService.isFullyMounted(for: conversation)
    }

    func updateConversationPreview(for msg: ChatMessage) {
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

    // MARK: - Gateway Config

    func loadGateways() {
        if let data = UserDefaults.standard.data(forKey: gatewaysKey),
           let decoded = try? JSONDecoder().decode([GatewayConfig].self, from: data) {
            gateways = decoded
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
            disconnect()
            activeGatewayId = ""
            UserDefaults.standard.removeObject(forKey: activeGatewayKey)
        }
    }

    // MARK: - Connect

    func connect(to config: GatewayConfig) async {
        isConnecting = true
        connectionError = nil

        // Precheck with temporary client
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

        // Precheck passed — do the real switch
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
            isConnected = true
            isPairingRequired = false
            isConnecting = false

            if let rawAgents = try? await gateway.listAgents() {
                agentList = buildAgentList(rawAgents)
            }

            if let result = try? await gateway.listSessions(limit: 1000),
               let sessions = result["sessions"] as? [[String: Any]] {

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
                    let displayName = session["displayName"] as? String ?? ""
                    let lastTo = session["lastTo"] as? String ?? ""
                    let deliveryTo = (session["deliveryContext"] as? [String: Any])?["to"] as? String ?? ""
                    let originProvider = (session["origin"] as? [String: Any])?["provider"] as? String ?? ""
                    if displayName == "heartbeat" || lastTo == "heartbeat"
                        || deliveryTo == "heartbeat" || originProvider == "heartbeat" { continue }

                    guard let agentId = MessageService.agentIdFromSessionKey(key),
                          let agentInfo = agentList.first(where: { $0.id == agentId }) else { continue }

                    let updatedAt = (session["updatedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantPast
                    let isA2A = key.contains(":subagent:")

                    if isA2A {
                        let parentKey = session["spawnedBy"] as? String ?? session["parentSessionKey"] as? String ?? ""
                        let parentAgentId = MessageService.agentIdFromSessionKey(parentKey) ?? "main"
                        let parentAgent = agentList.first(where: { $0.id == parentAgentId }) ?? agentInfo
                        let pairKey = [parentAgentId, agentId].sorted().joined(separator: ":")
                        if a2aGroups[pairKey] != nil {
                            a2aGroups[pairKey]!.keys.append(key)
                            if updatedAt > a2aGroups[pairKey]!.latestUpdatedAt { a2aGroups[pairKey]!.latestUpdatedAt = updatedAt }
                        } else {
                            a2aGroups[pairKey] = A2AGroupInfo(parentAgent: parentAgent, childAgent: agentInfo, keys: [key], latestUpdatedAt: updatedAt)
                        }
                    } else {
                        if userGroups[agentId] != nil {
                            userGroups[agentId]!.keys.append(key)
                            if updatedAt > userGroups[agentId]!.latestUpdatedAt { userGroups[agentId]!.latestUpdatedAt = updatedAt }
                        } else {
                            userGroups[agentId] = GroupInfo(agent: agentInfo, keys: [key], latestUpdatedAt: updatedAt)
                        }
                    }
                }

                for (agentId, group) in userGroups {
                    var conv = Conversation(id: "user:\(agentId)", sessionKey: group.keys.first ?? "",
                                            sessionKeys: group.keys, agentId: agentId,
                                            displayName: group.agent.name, avatar: group.agent.avatar,
                                            color: group.agent.color, kind: .user)
                    conv.lastTimestamp = group.latestUpdatedAt
                    conversations.append(conv)
                }

                for (pairKey, group) in a2aGroups {
                    var conv = Conversation(id: "a2a:\(pairKey)", sessionKey: group.keys.first ?? "",
                                            sessionKeys: group.keys, agentId: group.childAgent.id,
                                            displayName: group.parentAgent.name, avatar: group.parentAgent.avatar,
                                            color: group.parentAgent.color, kind: .a2a)
                    conv.secondaryAgentId = group.childAgent.id
                    conv.secondaryName = group.childAgent.name
                    conv.secondaryAvatar = group.childAgent.avatar
                    conv.lastTimestamp = group.latestUpdatedAt
                    conversations.append(conv)
                }
            }

            activeGatewayId = config.id
            UserDefaults.standard.set(config.id, forKey: activeGatewayKey)

            loadCachedMessages()
            updateConversationPreviews()

            let snapshot = conversations
            Task {
                for conv in snapshot {
                    await fetchAllSessions(for: conv)
                }
            }

        } catch {
            isConnecting = false
            if let gwErr = error as? GatewayClientError, case .pairingRequired(let deviceId, let requestId) = gwErr {
                isPairingRequired = true
                pairingDeviceId = deviceId
                pairingRequestId = requestId
            } else {
                connectionError = error.localizedDescription
                isPairingRequired = false
                isConnected = false
            }
        }
    }

    func disconnect() {
        gateway.disconnect()
        isConnected = false
    }

    // MARK: - Send Message

    func sendMessage(sessionKey: String, agentId: String, text: String, imageData: Data? = nil) async {
        var msg = ChatMessage(
            id: "local-\(Date().timeIntervalSince1970)",
            sessionKey: sessionKey, agentId: agentId,
            role: .user, text: text.isEmpty && imageData != nil ? "" : text,
            timestamp: Date(), runId: nil
        )
        msg.localImageData = imageData
        messageService.addMessage(msg)
        messageService.updateAgent(agentId, status: .working, task: String(text.prefix(80)))

        if isMockMode {
            mockAgentReply(sessionKey: sessionKey, agentId: agentId, userText: text)
            return
        }

        do {
            var attachments: [[String: Any]]?
            if let imageData {
                attachments = [["type": "image", "mimeType": "image/jpeg", "content": imageData.base64EncodedString()]]
            }
            let msgText = text.isEmpty ? "请看图片" : text
            try await gateway.sendChat(sessionKey: sessionKey, message: msgText, attachments: attachments)
        } catch {
            NSLog("[store] sendChat error: %@", "\(error)")
        }
    }

    private func mockAgentReply(sessionKey: String, agentId: String, userText: String) {
        let agentName = agentList.first(where: { $0.id == agentId })?.name ?? "Agent"
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            messageService.updateAgent(agentId, status: .working, streaming: .some("思考中..."))
            try? await Task.sleep(for: .seconds(1.0))
            let reply = "收到「\(userText)」。\(agentName)已处理完毕，一切正常。"
            messageService.updateAgent(agentId, status: .working, streaming: .some(reply))
            try? await Task.sleep(for: .seconds(1.0))
            messageService.updateAgent(agentId, status: .idle, streaming: .some(nil))
            messageService.addMessage(ChatMessage(
                id: "mock-reply-\(Date().timeIntervalSince1970)",
                sessionKey: sessionKey, agentId: agentId, role: .agent,
                text: reply, timestamp: Date(), runId: nil
            ))
        }
    }

    // MARK: - Fetch Sessions

    func fetchAllSessions(for conversation: Conversation) async {
        let keys = conversation.allSessionKeys
        let startIndex = conversation.loadedSessionCount
        for index in startIndex..<keys.count {
            let key = keys[index]
            let agentId = MessageService.agentIdFromSessionKey(key) ?? conversation.agentId
            if let hist = try? await gateway.chatHistory(sessionKey: key, limit: 100) {
                messageService.parseHistory(hist, sessionKey: key, agentId: agentId)
            }
            if let i = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[i].loadedSessionCount = index + 1
                if !conversations[i].historyLoaded { conversations[i].historyLoaded = true }
                if index + 1 >= keys.count { conversations[i].fullyLoaded = true }
            }
        }
        updateConversationPreviews()
    }

    func fetchNextSession(for conversation: Conversation) async {
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
        let agentId = MessageService.agentIdFromSessionKey(key) ?? conversation.agentId
        if let hist = try? await gateway.chatHistory(sessionKey: key, limit: 100) {
            messageService.parseHistory(hist, sessionKey: key, agentId: agentId)
        }
        if let i = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[i].loadedSessionCount = nextIndex + 1
            if nextIndex + 1 >= keys.count { conversations[i].fullyLoaded = true }
        }
        updateConversationPreviews()
    }

    // MARK: - Private

    private func handleEvent(_ event: String, payload: [String: Any]) {
        switch event {
        case "agent":
            messageService.handleAgentEvent(payload)
        case "chat":
            messageService.handleChatEvent(payload)
        case "presence", "agent.status":
            if let agentId = payload["agentId"] as? String,
               let statusStr = payload["status"] as? String,
               let status = AgentStatus(rawValue: statusStr) {
                messageService.updateAgent(agentId, status: status, task: payload["task"] as? String)
            }
        default:
            break
        }
    }

    private func buildAgentList(_ raw: [[String: Any]]) -> [AgentInfo] {
        raw.enumerated().map { i, a in
            let id = a["agentId"] as? String ?? a["id"] as? String ?? UUID().uuidString
            let serverAvatar = a["avatar"] as? String ?? a["emoji"] as? String ?? a["icon"] as? String ?? ""
            let avatar = serverAvatar.isEmpty ? avatars[i % avatars.count] : serverAvatar
            let serverColor = a["color"] as? String ?? ""
            let color = serverColor.isEmpty ? colors[i % colors.count] : serverColor
            return AgentInfo(id: id, name: a["name"] as? String ?? "Agent", avatar: avatar, color: color)
        }
    }

    // MARK: - Mock Data

    func loadMockData() { MockDataProvider.load(into: self) }
}
