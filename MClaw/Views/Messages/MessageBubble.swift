import SwiftUI

private let mcGreen = Theme.green
private let mcBg = Theme.bg
// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    let agentAvatar: String
    var senderName: String? = nil  // shown for A2A conversations

    var isUser: Bool { message.role == .user }

    var timeString: String { formatBubbleTime(message.timestamp) }

    @State private var fullscreenImage: UIImage? = nil

    private var textOnly: String { stripImagesFromText(message.text) }
    private var hasText: Bool { !textOnly.isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 50)
            } else {
                ZStack {
                    Circle()
                        .fill(mcGreen.opacity(0.1))
                        .frame(width: 28, height: 28)
                    AvatarIcon(avatar: agentAvatar, color: mcGreen, size: 28)
                }
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if let name = senderName {
                    Text(name)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 4)
                }
                // Text bubble
                if hasText {
                    SelectableText(text: textOnly, fontSize: 14)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            isUser ? AnyShapeStyle(mcGreen.opacity(0.2)) : AnyShapeStyle(Color.white.opacity(0.06))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isUser ? mcGreen.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                        )
                }

                // Local image (sent by user)
                if let imgData = message.localImageData, let uiImage = UIImage(data: imgData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { fullscreenImage = uiImage }
                }

                HStack(spacing: 4) {
                    Text(timeString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))

                    if let status = message.sendStatus {
                        switch status {
                        case .sending:
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white.opacity(0.3))
                        case .sent:
                            Image(systemName: "checkmark")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.3))
                        case .failed:
                            Button {
                                // TODO: retry
                            } label: {
                                Image(systemName: "exclamationmark.circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            if !isUser {
                Spacer(minLength: 50)
            }
        }
        .fullScreenCover(item: $fullscreenImage) { img in
            ImageViewer(image: img)
        }
    }
}
