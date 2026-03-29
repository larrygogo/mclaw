import SwiftUI

private let mcGreen = Theme.green

// MARK: - Rich Message Content (images + text)

struct MessageContentView: View {
    let text: String
    var localImageData: Data? = nil
    @State private var fullscreenImage: UIImage? = nil

    private var parts: [MessagePart] { parseMessageParts(text) }

    var body: some View {
        let content = Group {
        if let imgData = localImageData, let uiImage = UIImage(data: imgData) {
            VStack(alignment: .leading, spacing: 6) {
                if !text.isEmpty {
                    SelectableText(text: text, fontSize: 14)
                }
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))
                    .onTapGesture { fullscreenImage = uiImage }
            }
        } else if parts.count == 1 && parts[0].kind == .text {
            SelectableText(text: parts[0].value, fontSize: 14)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    switch part.kind {
                    case .text:
                        SelectableText(text: part.value, fontSize: 14)
                    case .image:
                        if part.value.hasPrefix("data:image"),
                           let dataRange = part.value.range(of: "base64,"),
                           let data = Data(base64Encoded: String(part.value[dataRange.upperBound...]).replacingOccurrences(of: "\n", with: "")),
                           let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 240)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))
                        } else {
                            AsyncImage(url: URL(string: part.value)) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFit()
                                        .frame(maxWidth: 240)
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))
                                case .failure:
                                    HStack(spacing: 4) {
                                        Image(systemName: "photo").foregroundStyle(.white.opacity(0.3))
                                        Text("图片加载失败").font(.system(size: 11)).foregroundStyle(.white.opacity(0.3))
                                    }
                                default:
                                    ProgressView().tint(mcGreen)
                                }
                            }
                        }
                    }
                }
            }
        }
        }
        content
            .fullScreenCover(item: $fullscreenImage) { img in
                ImageViewer(image: img)
            }
    }
}
