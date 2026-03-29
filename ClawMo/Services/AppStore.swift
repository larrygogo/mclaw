import Foundation
import SwiftUI
import SwiftData

private let gatewaysKey = "clawmo-gateways"
private let activeGatewayKey = "clawmo-active-gateway"

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
    var scrollOffsets: [String: CGFloat] = [:]    // conversationId → UITableView contentOffset.y
    var draftTexts: [String: String] = [:]           // conversationId → draft input text

    // Hidden conversations
    var hiddenConversationIds: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(hiddenConversationIds), forKey: "clawmo-hidden-conversations")
        }
    }

    // Sync
    var backgroundedAt: Date?
    private var isSyncing = false

    // Navigation
    var selectedTab = 0
    var pendingConversationId: String?
    var pendingAgent: AgentInfo?

    let gateway = GatewayClient()
    let persistence: PersistenceService
    let networkMonitor = NetworkMonitor()
    private(set) var messageService: MessageService!
    private var networkObserver: Any?

    // MARK: - Init

    init(modelContainer: ModelContainer? = nil) {
        self.persistence = PersistenceService(modelContainer: modelContainer)
        loadGateways()
        if let hidden = UserDefaults.standard.array(forKey: "clawmo-hidden-conversations") as? [String] {
            hiddenConversationIds = Set(hidden)
        }
        self.messageService = MessageService(store: self)
        gateway.onEvent { [weak self] event, payload in
            self?.handleEvent(event, payload: payload)
        }
        networkMonitor.start()
        networkObserver = NotificationCenter.default.addObserver(forName: .networkRestored, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.gateway.isConnected, !self.isMockMode,
                  let active = self.gateways.first(where: { $0.id == self.activeGatewayId }) else { return }
            Task { await self.connect(to: active) }
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

    func updatePersistedMessageId(oldId: String, newId: String) {
        persistence.updateMessageId(oldId: oldId, newId: newId)
    }

    func hideConversation(_ id: String) {
        hiddenConversationIds.insert(id)
        Haptics.light()
    }

    func unhideConversation(_ id: String) {
        hiddenConversationIds.remove(id)
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
        // Try Keychain first
        if let data = KeychainService.load(key: gatewaysKey),
           let decoded = try? JSONDecoder().decode([GatewayConfig].self, from: data) {
            gateways = decoded
        }
        // Migrate from UserDefaults if Keychain empty
        else if let data = UserDefaults.standard.data(forKey: gatewaysKey),
                let decoded = try? JSONDecoder().decode([GatewayConfig].self, from: data) {
            gateways = decoded
            KeychainService.save(key: gatewaysKey, data: data)
            UserDefaults.standard.removeObject(forKey: gatewaysKey)
            NSLog("[store] migrated gateway configs from UserDefaults to Keychain")
        }
        activeGatewayId = UserDefaults.standard.string(forKey: activeGatewayKey) ?? ""
    }

    func saveGateways() {
        if let data = try? JSONEncoder().encode(gateways) {
            KeychainService.save(key: gatewaysKey, data: data)
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
        // Mock gateway: load test data without connecting
        if config.url == "mock://test" {
            loadMockData()
            activeGatewayId = config.id
            UserDefaults.standard.set(config.id, forKey: "clawmo-active-gateway")
            return
        }

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
            Haptics.success()

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

    // MARK: - Background Task Helper

    private func withBackgroundTask<T>(name: String, _ body: () async throws -> T) async rethrows -> T {
        let taskId = UIApplication.shared.beginBackgroundTask(withName: name) { }
        defer {
            if taskId != .invalid { UIApplication.shared.endBackgroundTask(taskId) }
        }
        return try await body()
    }

    // MARK: - Send Message

    func sendMessage(sessionKey: String, agentId: String, text: String, imageData: Data? = nil, fileSize: Int64? = nil) async {
        let msgId = "local-\(Date().timeIntervalSince1970)"
        var msg = ChatMessage(
            id: msgId,
            sessionKey: sessionKey, agentId: agentId,
            role: .user, text: text.isEmpty && imageData != nil ? "" : text,
            timestamp: Date(), runId: nil
        )
        msg.localImageData = imageData
        msg.fileSize = fileSize
        msg.sendStatus = .sending
        messageService.addMessage(msg)
        messageService.updateAgent(agentId, status: .working, task: String(text.prefix(80)))
        Haptics.light()

        if isMockMode {
            if text.lowercased().contains("fail") {
                updateMessageStatus(id: msgId, status: .failed)
            } else {
                updateMessageStatus(id: msgId, status: .sent)
                mockAgentReply(sessionKey: sessionKey, agentId: agentId, userText: text)
            }
            return
        }

        await withBackgroundTask(name: "sendMessage") {
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
    }

    func retryMessage(_ msg: ChatMessage) async {
        // Reuse existing message — just flip status to .sending
        // This prevents duplicate messages from multiple retry taps
        guard let i = messages.firstIndex(where: { $0.id == msg.id }),
              messages[i].sendStatus == .failed else { return }
        let current = messages[i]
        messages[i].sendStatus = .sending
        Haptics.medium()

        if isMockMode {
            updateMessageStatus(id: current.id, status: .sent)
            return
        }

        await withBackgroundTask(name: "retryMessage") {
            do {
                var attachments: [[String: Any]]?
                if let imageData = current.localImageData {
                    attachments = [["type": "image", "mimeType": "image/jpeg", "content": imageData.base64EncodedString()]]
                }
                let msgText = current.text.isEmpty ? "请看图片" : current.text
                try await gateway.sendChat(sessionKey: current.sessionKey, message: msgText, attachments: attachments)
                updateMessageStatus(id: current.id, status: .sent)
            } catch {
                NSLog("[store] retry sendChat error: %@", "\(error)")
                updateMessageStatus(id: current.id, status: .failed)
            }
        }
    }

    private func updateMessageStatus(id: String, status: MessageSendStatus) {
        if let i = messages.firstIndex(where: { $0.id == id }) {
            let oldStatus = messages[i].sendStatus
            messages[i].sendStatus = status
            // Haptic on status transitions
            if oldStatus == .sending && status == .sent { Haptics.success() }
            if status == .failed { Haptics.error() }
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

    // MARK: - Scene Phase & Sync

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            if backgroundedAt == nil { backgroundedAt = Date() }
        case .active:
            let offlineAt = backgroundedAt
            backgroundedAt = nil
            guard !isMockMode else { return }

            if !gateway.isConnected {
                // Disconnected while in background — reconnect (triggers full sync)
                if let active = gateways.first(where: { $0.id == activeGatewayId }) {
                    Task { await connect(to: active) }
                }
            } else if let offlineAt {
                // Still connected — do incremental sync for the gap
                let minutes = max(1, Int(Date().timeIntervalSince(offlineAt) / 60) + 1)
                Task { await syncMessages(activeMinutes: minutes) }
            }
        @unknown default:
            break
        }
    }

    func syncMessages(activeMinutes: Int) async {
        guard isConnected, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        NSLog("[sync] incremental sync, activeMinutes=%d", activeMinutes)
        guard let result = try? await gateway.listSessions(limit: 1000, activeMinutes: activeMinutes),
              let sessions = result["sessions"] as? [[String: Any]] else { return }

        let activeKeys = sessions.compactMap { $0["key"] as? String }
        NSLog("[sync] %d sessions active in last %d min", activeKeys.count, activeMinutes)

        for key in activeKeys {
            let agentId = MessageService.agentIdFromSessionKey(key) ?? "main"
            if let hist = try? await gateway.chatHistory(sessionKey: key, limit: 200) {
                messageService.parseHistory(hist, sessionKey: key, agentId: agentId)
            }
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
