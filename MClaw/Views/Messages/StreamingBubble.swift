import SwiftUI

private let mcGreen = Theme.green
private let mcBg = Theme.bg
// MARK: - Streaming Bubble

struct StreamingBubble: View {
    let text: String
    let avatar: String

    var attributedText: AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle()
                    .fill(mcGreen.opacity(0.1))
                    .frame(width: 28, height: 28)
                AvatarIcon(avatar: avatar, color: mcGreen, size: 28)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(attributedText)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )

                Text("输入中...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(mcGreen.opacity(0.5))
                    .padding(.horizontal, 4)
            }
            Spacer(minLength: 50)
        }
    }
}
