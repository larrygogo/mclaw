import Foundation

/// Isolated observable for high-frequency message state.
/// Only Views that need messages/agentStates should reference this,
/// preventing OfficeView/SettingsView from re-rendering on every message.
@MainActor @Observable
final class ChatState {
    var messages: [ChatMessage] = []
    var agentStates: [String: AgentState] = [:]
    var mountedCounts: [String: Int] = [:]
    var scrollOffsets: [String: CGFloat] = [:]
    var draftTexts: [String: String] = [:]
}
