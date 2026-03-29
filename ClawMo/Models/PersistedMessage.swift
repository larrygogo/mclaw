import Foundation
import SwiftData

@Model
final class PersistedMessage {
    @Attribute(.unique) var stableId: String
    var gatewayId: String
    var sessionKey: String
    var agentId: String
    var role: String
    var text: String
    var timestamp: Date
    var runId: String?
    @Attribute(.externalStorage) var imageData: Data?
    var fileSize: Int64?

    init(stableId: String, gatewayId: String, sessionKey: String, agentId: String,
         role: String, text: String, timestamp: Date, runId: String?, imageData: Data? = nil, fileSize: Int64? = nil) {
        self.stableId = stableId
        self.gatewayId = gatewayId
        self.sessionKey = sessionKey
        self.agentId = agentId
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.runId = runId
        self.imageData = imageData
        self.fileSize = fileSize
    }
}

extension PersistedMessage {
    convenience init(from msg: ChatMessage, gatewayId: String) {
        self.init(stableId: msg.id, gatewayId: gatewayId, sessionKey: msg.sessionKey,
                  agentId: msg.agentId, role: msg.role.rawValue, text: msg.text,
                  timestamp: msg.timestamp, runId: msg.runId, imageData: msg.localImageData,
                  fileSize: msg.fileSize)
    }

    func toChatMessage() -> ChatMessage {
        var msg = ChatMessage(id: stableId, sessionKey: sessionKey, agentId: agentId,
                    role: MessageRole(rawValue: role) ?? .system,
                    text: text, timestamp: timestamp, runId: runId)
        msg.localImageData = imageData
        msg.fileSize = fileSize
        return msg
    }
}
