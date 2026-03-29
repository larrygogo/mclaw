import SwiftUI

struct ConversationRow: View {
    let conversation: Conversation
    @Environment(AppStore.self) var store

    private var latestMessage: ChatMessage? {
        let keys = Set(conversation.allSessionKeys)
        return store.messages
            .filter { keys.contains($0.sessionKey) && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .max { $0.timestamp < $1.timestamp }
    }

    var previewText: String {
        if let msg = latestMessage {
            if msg.isFileMessage { return "[文件] \(msg.fileInfo?.name ?? "")" }
            if msg.localImageData != nil { return "[图片]" }
            let trimmed = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed.prefix(60))
        }
        return conversation.historyLoaded ? "暂无消息" : "加载中..."
    }

    var timeString: String {
        let ts = latestMessage?.timestamp ?? conversation.lastTimestamp
        guard ts > .distantPast else { return "" }
        return formatRowTime(ts)
    }

    var body: some View {
        HStack(spacing: 14) {
            if conversation.kind == .a2a {
                let cellSize: CGFloat = 20
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: conversation.color).opacity(0.15))
                            AvatarIcon(
                                avatar: conversation.avatar,
                                color: Color(hex: conversation.color),
                                size: cellSize, agentId: conversation.agentId
                            )
                        }
                        .frame(width: cellSize, height: cellSize)

                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.06))
                            AvatarIcon(
                                avatar: conversation.secondaryAvatar,
                                color: .white.opacity(0.5),
                                size: cellSize,
                                agentId: conversation.secondaryAgentId
                            )
                        }
                        .frame(width: cellSize, height: cellSize)
                    }
                }
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                .frame(width: 48, height: 48)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: conversation.color).opacity(0.15))
                        .frame(width: 48, height: 48)
                    AvatarIcon(avatar: conversation.avatar, color: Color(hex: conversation.color), size: 48, agentId: conversation.agentId)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if conversation.kind == .a2a {
                        HStack(spacing: 4) {
                            Text(conversation.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("↔")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.3))
                            Text(conversation.secondaryName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .lineLimit(1)
                    } else {
                        Text(conversation.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(timeString)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
                Text(previewText)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
