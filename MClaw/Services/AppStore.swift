import Foundation
import SwiftData

private let gatewaysKey = "mclaw-gateways"
private let activeGatewayKey = "mclaw-active-gateway"

@MainActor @Observable
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
        let text = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || msg.localImageData != nil else { return }
        guard let i = conversations.firstIndex(where: { $0.allSessionKeys.contains(msg.sessionKey) }) else { return }
        if conversations[i].lastMessageText.isEmpty || msg.timestamp >= conversations[i].lastTimestamp {
            let preview = msg.localImageData != nil ? "[图片]" : String(text.prefix(60))
            conversations[i].lastMessageText = preview
            conversations[i].lastTimestamp = msg.timestamp
        }
    }

    func updateConversationPreviews() {
        for i in conversations.indices {
            let keys = Set(conversations[i].allSessionKeys)
            let matched = messages.filter { keys.contains($0.sessionKey) }
            let withText = matched.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.localImageData != nil }
            if let last = withText.max(by: { $0.timestamp < $1.timestamp }) {
                let trimmed = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let preview = last.localImageData != nil ? "[图片]" : String(trimmed.prefix(60))
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
                agentList = ConversationService.buildAgentList(rawAgents)
            }

            if let result = try? await gateway.listSessions(limit: 1000),
               let sessions = result["sessions"] as? [[String: Any]] {
                conversations = ConversationService.buildConversations(from: sessions, agents: agentList)
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
        let msgId = "local-\(Date().timeIntervalSince1970)"
        var msg = ChatMessage(
            id: msgId,
            sessionKey: sessionKey, agentId: agentId,
            role: .user, text: text.isEmpty && imageData != nil ? "" : text,
            timestamp: Date(), runId: nil
        )
        msg.localImageData = imageData
        msg.sendStatus = .sending
        messageService.addMessage(msg)
        messageService.updateAgent(agentId, status: .working, task: String(text.prefix(80)))

        if isMockMode {
            updateMessageStatus(id: msgId, status: .sent)
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
            updateMessageStatus(id: msgId, status: .sent)
        } catch {
            NSLog("[store] sendChat error: %@", "\(error)")
            updateMessageStatus(id: msgId, status: .failed)
        }
    }

    private func updateMessageStatus(id: String, status: MessageSendStatus) {
        if let i = messages.firstIndex(where: { $0.id == id }) {
            messages[i].sendStatus = status
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

    // MARK: - Mock Data

    func loadMockData() { MockDataProvider.load(into: self) }
}
