import Foundation
import SwiftUI

// MARK: - Gateway

struct GatewayConfig: Codable, Identifiable, Equatable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var url: String
    var token: String
}

// MARK: - Agent

struct AgentInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let avatar: String
    let color: String
}

enum AgentStatus: String, Codable {
    case working, idle, waiting, offline
}

struct AgentState {
    var id: String
    var status: AgentStatus = .offline
    var currentTask: String?
    var lastActivity: Date?
    var streamingText: String?
    var lastError: String?
}

// MARK: - Conversation

enum ConversationKind: Hashable {
    case user   // 我的：用户直接发起的对话
    case a2a    // 员工：agent 之间的对话
}

struct Conversation: Identifiable, Hashable {
    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id && lhs.lastMessageText == rhs.lastMessageText && lhs.lastTimestamp == rhs.lastTimestamp
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id: String
    let sessionKey: String       // primary session key (user conversations)
    var sessionKeys: [String] = [] // all session keys (A2A grouped conversations)
    let agentId: String
    let displayName: String
    let avatar: String
    let color: String
    let kind: ConversationKind
    // A2A only: the other party in the conversation
    var secondaryAgentId: String = ""
    var secondaryName: String = ""
    var secondaryAvatar: String = "cpu"
    var lastMessageText: String = ""
    var lastTimestamp: Date = .distantPast
    var historyLoaded: Bool = false      // initial batch loaded
    var fullyLoaded: Bool = false        // all sessions loaded
    var loadedSessionCount: Int = 0      // how many session keys have been loaded

    /// All session keys this conversation covers
    var allSessionKeys: [String] {
        sessionKeys.isEmpty ? [sessionKey] : sessionKeys
    }
}

// MARK: - File Info

struct FileInfo: Equatable {
    let name: String
    let ext: String

    var icon: String {
        switch ext.lowercased() {
        case "pdf":                                                 return "doc.richtext"
        case "doc", "docx":                                         return "doc.text"
        case "xls", "xlsx", "csv":                                  return "tablecells"
        case "ppt", "pptx", "key":                                  return "rectangle.on.rectangle"
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "heic":   return "photo"
        case "psd", "ai", "sketch", "fig", "xd":                   return "paintbrush"
        case "mp4", "mov", "avi", "mkv":                            return "film"
        case "mp3", "wav", "aac", "flac", "m4a":                   return "music.note"
        case "zip", "rar", "7z", "tar", "gz":                      return "doc.zipper"
        case "json", "xml", "yaml", "yml", "toml":                  return "curlybraces"
        case "swift", "js", "ts", "py", "go", "rs", "java", "c", "cpp", "h":
                                                                    return "chevron.left.forwardslash.chevron.right"
        case "md", "txt", "rtf":                                    return "doc.plaintext"
        default:                                                    return "doc"
        }
    }

    var iconColor: Color {
        switch ext.lowercased() {
        case "pdf":                                                 return .red
        case "doc", "docx":                                         return .blue
        case "xls", "xlsx", "csv":                                  return .green
        case "ppt", "pptx", "key":                                  return .orange
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "heic", "psd":
                                                                    return .purple
        case "zip", "rar", "7z", "tar", "gz":                      return .yellow
        case "json", "xml", "yaml", "yml", "toml", "swift", "js", "ts", "py":
                                                                    return .cyan
        default:                                                    return .gray
        }
    }

    static func parse(from text: String) -> FileInfo? {
        let pattern = /^\[文件[:：]\s*(.+)\]$/
        guard let match = text.wholeMatch(of: pattern) else { return nil }
        let name = String(match.1)
        let ext = (name as NSString).pathExtension
        return FileInfo(name: name, ext: ext)
    }

    static func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024
        return String(format: "%.1f GB", gb)
    }
}

// MARK: - Message

enum MessageSendStatus: Equatable {
    case sent       // delivered to gateway
    case sending    // in flight
    case failed     // send failed
}

struct ChatMessage: Identifiable, Equatable {
    var id: String
    let sessionKey: String
    let agentId: String
    let role: MessageRole
    let text: String
    let timestamp: Date
    let runId: String?
    var localImageData: Data?
    var sendStatus: MessageSendStatus?  // nil = received from server
    var fileSize: Int64?

    var fileInfo: FileInfo? { FileInfo.parse(from: text) }
    var isFileMessage: Bool { fileInfo != nil }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

enum MessageRole: String {
    case agent, user, system
}
