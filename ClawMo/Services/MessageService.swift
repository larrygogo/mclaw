import Foundation

enum OptionalValue<T> {
    case none, some(T?)
}

final class MessageService {
    weak var store: AppStore?
    var runTexts: [String: String] = [:]

    init(store: AppStore) {
        self.store = store
    }

    // MARK: - Mount (display window from local cache)

    func mountedMessages(for conversation: Conversation) -> [ChatMessage] {
        guard let store else { return [] }
        let keys = Set(conversation.allSessionKeys)
        let all = store.messages.filter { keys.contains($0.sessionKey) }
                      .sorted { $0.timestamp < $1.timestamp }
        let count = store.mountedCounts[conversation.id] ?? 30
        if all.count <= count { return all }
        return Array(all.suffix(count))
    }

    func mountMore(for conversation: Conversation) {
        guard let store else { return }
        let keys = Set(conversation.allSessionKeys)
        let totalAvailable = store.messages.filter { keys.contains($0.sessionKey) }.count
        let current = store.mountedCounts[conversation.id] ?? 30
        store.mountedCounts[conversation.id] = min(current + 30, totalAvailable)

        if current + 30 >= totalAvailable, !conversation.fullyLoaded {
            Task { await store.fetchNextSession(for: conversation) }
        }
        store.updateConversationPreviews()
    }

    func isFullyMounted(for conversation: Conversation) -> Bool {
        guard let store else { return true }
        let keys = Set(conversation.allSessionKeys)
        let total = store.messages.filter { keys.contains($0.sessionKey) }.count
        let mounted = store.mountedCounts[conversation.id] ?? 30
        return mounted >= total && conversation.fullyLoaded
    }

    // MARK: - Add message with dedup

    func addMessage(_ msg: ChatMessage) {
        guard let store else { return }

        // If server message matches a locally sent message, unify the ID
        if !msg.id.hasPrefix("local-"),
           let localIdx = store.messages.firstIndex(where: {
               $0.id.hasPrefix("local-")
               && $0.sessionKey == msg.sessionKey && $0.role == msg.role && $0.text == msg.text
               && abs($0.timestamp.timeIntervalSince(msg.timestamp)) < 60
           }) {
            store.messages[localIdx].id = msg.id
            return
        }

        guard !store.messages.contains(where: {
            $0.id == msg.id ||
            ($0.sessionKey == msg.sessionKey && $0.role == msg.role && $0.text == msg.text
             && abs($0.timestamp.timeIntervalSince(msg.timestamp)) < 5)
        }) else { return }
        store.messages.append(msg)
        if store.messages.count > 2000 {
            store.messages.removeFirst(store.messages.count - 2000)
        }
        store.persistMessages([msg])
        store.updateConversationPreviews()
    }

    // MARK: - Event handlers

    func handleAgentEvent(_ payload: [String: Any]) {
        guard let _ = store else { return }
        guard let sessionKey = payload["sessionKey"] as? String,
              let agentId = Self.agentIdFromSessionKey(sessionKey),
              let stream = payload["stream"] as? String else { return }

        let data = payload["data"] as? [String: Any]
        let runId = payload["runId"] as? String

        if stream == "lifecycle", let data {
            switch data["phase"] as? String {
            case "start":
                updateAgent(agentId, status: .working, streaming: .some(""))
            case "end":
                updateAgent(agentId, status: .idle, streaming: .some(nil))
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

    func handleChatEvent(_ payload: [String: Any]) {
        guard let _ = store else { return }
        guard payload["state"] as? String == "final",
              let sessionKey = payload["sessionKey"] as? String,
              let agentId = Self.agentIdFromSessionKey(sessionKey),
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

        let openclawId = (message["__openclaw"] as? [String: Any])?["id"] as? String
        let msgId = openclawId ?? runId ?? "chat-\(sessionKey)-\(Int(ts.timeIntervalSince1970 * 1000))"

        addMessage(ChatMessage(
            id: msgId, sessionKey: sessionKey, agentId: agentId,
            role: role == "assistant" ? .agent : .user,
            text: text, timestamp: ts, runId: runId
        ))
    }

    // MARK: - Parse history

    func parseHistory(_ hist: [String: Any], sessionKey: String, agentId: String) {
        guard let store else { return }
        guard let msgs = hist["messages"] as? [[String: Any]] else { return }
        var newMessages: [ChatMessage] = []

        for m in msgs {
            let role = m["role"] as? String
            guard role == "user" || role == "assistant" else { continue }
            let ts = (m["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
            let content = m["content"] as? [[String: Any]] ?? []
            let textParts = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
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
            guard !trimmed.contains("HEARTBEAT") else { continue }
            if m["provenance"] != nil { continue }

            let openclaw = m["__openclaw"] as? [String: Any]
            let msgId = openclaw?["id"] as? String
                ?? "hist-\(sessionKey)-\(openclaw?["seq"] as? Int ?? Int(ts.timeIntervalSince1970))-\(role ?? "x")"

            let msgRole: MessageRole = role == "assistant" ? .agent : .user

            // If history message matches a locally sent message, unify the ID
            if let localIdx = store.messages.firstIndex(where: {
                $0.id.hasPrefix("local-")
                && $0.sessionKey == sessionKey && $0.role == msgRole && $0.text == text
                && abs($0.timestamp.timeIntervalSince(ts)) < 60
            }) {
                store.messages[localIdx].id = msgId
                continue
            }

            let isDuplicate = store.messages.contains(where: {
                $0.id == msgId ||
                ($0.sessionKey == sessionKey && $0.role == msgRole && $0.text == text
                 && abs($0.timestamp.timeIntervalSince(ts)) < 5)
            })
            guard !isDuplicate else { continue }
            guard !newMessages.contains(where: {
                $0.id == msgId ||
                ($0.sessionKey == sessionKey && $0.role == msgRole && $0.text == text
                 && abs($0.timestamp.timeIntervalSince(ts)) < 5)
            }) else { continue }

            newMessages.append(ChatMessage(
                id: msgId, sessionKey: sessionKey, agentId: agentId,
                role: msgRole, text: text, timestamp: ts, runId: nil
            ))
        }

        if !newMessages.isEmpty {
            store.messages.append(contentsOf: newMessages)
            if store.messages.count > 2000 {
                store.messages.removeFirst(store.messages.count - 2000)
            }
            if let latest = newMessages.max(by: { $0.timestamp < $1.timestamp }) {
                store.updateConversationPreview(for: latest)
            }
            store.persistMessages(newMessages)
        }
    }

    // MARK: - Helpers

    func updateAgent(_ id: String, status: AgentStatus? = nil,
                     task: String? = nil, streaming: OptionalValue<String> = .none) {
        guard let store else { return }
        var state = store.agentStates[id] ?? AgentState(id: id)
        if let s = status { state.status = s }
        if let t = task { state.currentTask = t }
        if case .some(let v) = streaming { state.streamingText = v }
        state.lastActivity = Date()
        store.agentStates[id] = state
    }

    static func agentIdFromSessionKey(_ key: String) -> String? {
        let parts = key.split(separator: ":")
        return parts.count >= 2 ? String(parts[1]) : nil
    }
}
