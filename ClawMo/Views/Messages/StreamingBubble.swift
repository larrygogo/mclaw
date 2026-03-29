import SwiftUI

private let mcGreen = Theme.green
private let mcBg = Theme.bg
// MARK: - Streaming Bubble

struct StreamingBubble: View {
    let text: String
    let avatar: String
    var agentId: String?

    var attributedText: AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(mcGreen.opacity(0.1))
                    .frame(width: 28, height: 28)
                AvatarIcon(avatar: avatar, color: mcGreen, size: 28, agentId: agentId)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(attributedText)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.surface2)
                    .foregroundStyle(Theme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))

                Text("输入中...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(mcGreen.opacity(0.5))
                    .padding(.horizontal, 4)
            }
            Spacer(minLength: 50)
        }
    }
}
