import SwiftUI

// MARK: - A2A Message Bubble (both sides on left)

struct A2AMessageBubble: View {
    let message: ChatMessage
    let conversation: Conversation

    // user role = orchestrator (parent agent), assistant role = subagent
    var isOrchestrator: Bool { message.role == .user }

    var name: String { isOrchestrator ? conversation.displayName : conversation.secondaryName }
    var avatar: String { isOrchestrator ? conversation.avatar : conversation.secondaryAvatar }
    var bubbleColor: Color { isOrchestrator ? Color(hex: conversation.color).opacity(0.15) : Color.white.opacity(0.06) }
    var avatarColor: Color { isOrchestrator ? Color(hex: conversation.color) : .white.opacity(0.5) }

    var timeString: String { formatA2ABubbleTime(message.timestamp) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(avatarColor.opacity(0.15)).frame(width: 28, height: 28)
                    AvatarIcon(avatar: avatar, color: avatarColor, size: 28)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(avatarColor)

                SelectableText(text: message.text, fontSize: 14)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))

                Text(timeString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.horizontal, 4)
            }

            Spacer(minLength: 40)
        }
    }
}
