import SwiftUI

private let mcGreen = Theme.green
private let mcBg = Theme.bg
// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    let agentAvatar: String
    var agentId: String?
    var senderName: String?
    var onRetry: (() -> Void)?
    @State private var showCopied = false

    var isUser: Bool { message.role == .user }

    var timeString: String { formatBubbleTime(message.timestamp) }

    @State private var fullscreenImage: UIImage?

    private var textOnly: String { stripImagesFromText(message.text) }
    private var hasText: Bool { !textOnly.isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser {
                Spacer(minLength: 50)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(mcGreen.opacity(0.1))
                        .frame(width: 28, height: 28)
                    AvatarIcon(avatar: agentAvatar, color: mcGreen, size: 28, agentId: agentId)
                }
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if let name = senderName {
                    Text(name)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 4)
                }
                // File bubble or text bubble
                if let fileInfo = message.fileInfo {
                    FileBubble(fileInfo: fileInfo, fileSize: message.fileSize,
                               fileData: message.localImageData, isUser: isUser)
                } else if hasText {
                    SelectableText(text: textOnly, fontSize: 14)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            isUser ? AnyShapeStyle(Color(red: 20/255, green: 46/255, blue: 28/255)) : AnyShapeStyle(Theme.surface2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = textOnly
                                Haptics.light()
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                            }
                            if message.sendStatus == .failed, let onRetry {
                                Button {
                                    onRetry()
                                } label: {
                                    Label("重试", systemImage: "arrow.clockwise")
                                }
                            }
                            Button {
                                shareText(textOnly)
                            } label: {
                                Label("分享", systemImage: "square.and.arrow.up")
                            }
                        }
                }

                // Local image (sent by user, skip for file messages)
                if !message.isFileMessage, let imgData = message.localImageData, let uiImage = UIImage(data: imgData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
                        .onTapGesture { fullscreenImage = uiImage }
                }

                HStack(spacing: 4) {
                    Text(timeString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)

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
                                onRetry?()
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

    private func shareText(_ text: String) {
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            if let popover = av.popoverPresentationController {
                popover.sourceView = root.view
                popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
            }
            root.present(av, animated: true)
        }
    }
}

// MARK: - File Bubble

struct FileBubble: View {
    let fileInfo: FileInfo
    let fileSize: Int64?
    let fileData: Data?
    let isUser: Bool

    @State private var showFullText = false
    @State private var menuDismissedAt: Date = .distantPast

    private var isTextFile: Bool {
        ["txt", "md", "json", "xml", "yaml", "yml", "toml", "csv",
         "swift", "js", "ts", "py", "go", "rs", "java", "c", "cpp", "h",
         "sql", "sh", "log", "rtf", "html", "css"].contains(fileInfo.ext.lowercased())
    }

    private var fullText: String? {
        guard isTextFile, let data = fileData, let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(fileInfo.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let size = fileSize {
                        Text(FileInfo.formatSize(size))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Text(fileInfo.ext.uppercased())
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.surface1)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            Spacer(minLength: 12)

            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusS)
                    .fill(Theme.surface1)
                    .frame(width: 44, height: 44)
                Image(systemName: fileInfo.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .frame(width: 240)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
        .overlay {
            if fileData != nil {
                EditMenuHost(menuDismissedAt: $menuDismissedAt, actions: [
                    .init(title: "存储", icon: "folder", handler: saveToFiles),
                    .init(title: "转发", icon: "square.and.arrow.up", handler: shareFile),
                ])
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            guard Date().timeIntervalSince(menuDismissedAt) > 0.5 else { return }
            if isTextFile && fullText != nil {
                showFullText = true
            }
        })
        .sheet(isPresented: $showFullText) {
            if let text = fullText {
                TextFileViewer(fileName: fileInfo.name, content: text)
            }
        }
    }

    private func tempFileURL() -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(fileInfo.name)
        try? fileData?.write(to: tmp)
        return tmp
    }

    private func saveToFiles() {
        let url = tempFileURL()
        let picker = UIDocumentPickerViewController(forExporting: [url])
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(picker, animated: true)
        }
    }

    private func shareFile() {
        let url = tempFileURL()
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            if let popover = av.popoverPresentationController {
                popover.sourceView = root.view
                popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
            }
            root.present(av, animated: true)
        }
    }
}

// MARK: - Text File Viewer

struct TextFileViewer: View {
    let fileName: String
    let content: String
    @Environment(\.dismiss) private var dismiss

    private let mcBg = Theme.bg

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(content)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
            }
            .background(mcBg)
            .navigationTitle(fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(.white.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = content
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .presentationBackground(mcBg)
    }
}

// MARK: - Edit Menu Host (UIEditMenuInteraction)

struct EditMenuAction {
    let title: String
    let icon: String
    let handler: () -> Void
}

struct EditMenuHost: UIViewRepresentable {
    @Binding var menuDismissedAt: Date
    let actions: [EditMenuAction]

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let interaction = UIEditMenuInteraction(delegate: context.coordinator)
        view.addInteraction(interaction)
        context.coordinator.interaction = interaction
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.cancelsTouchesInView = false
        view.addGestureRecognizer(longPress)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.actions = actions
        context.coordinator.dismissBinding = $menuDismissedAt
    }

    func makeCoordinator() -> Coordinator { Coordinator(actions: actions, dismissBinding: $menuDismissedAt) }

    class Coordinator: NSObject, UIEditMenuInteractionDelegate {
        var actions: [EditMenuAction]
        weak var interaction: UIEditMenuInteraction?
        var dismissBinding: Binding<Date>

        init(actions: [EditMenuAction], dismissBinding: Binding<Date>) {
            self.actions = actions
            self.dismissBinding = dismissBinding
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let interaction else { return }
            let location = gesture.location(in: gesture.view)
            let config = UIEditMenuConfiguration(identifier: nil, sourcePoint: location)
            interaction.presentEditMenu(with: config)
        }

        func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                                 menuFor configuration: UIEditMenuConfiguration,
                                 suggestedActions: [UIMenuElement]) -> UIMenu? {
            let items = actions.map { action in
                UIAction(title: action.title, image: UIImage(systemName: action.icon)) { _ in action.handler() }
            }
            return UIMenu(children: items)
        }

        func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                                 willDismissMenuFor configuration: UIEditMenuConfiguration) {
            DispatchQueue.main.async { self.dismissBinding.wrappedValue = Date() }
        }
    }
}
