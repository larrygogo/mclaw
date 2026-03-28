import SwiftUI
import PhotosUI
import Speech
import AVFoundation

private let mcGreen = Color(hex: "39ff14")
private let mcMint  = Color(hex: "b6ffa8")
private let mcBg    = Color(hex: "0a0a0f")

// MARK: - Message Center (Conversation List)

struct MessageCenterView: View {
    @Environment(AppStore.self) var store
    @State private var selectedConversation: Conversation?
    @State private var showSection: ConversationSection = .user

    enum ConversationSection: String, CaseIterable {
        case user = "我的"
        case a2a  = "员工"
    }

    var userConversations: [Conversation] {
        store.conversations.filter { $0.kind == .user }
                           .sorted { $0.lastTimestamp > $1.lastTimestamp }
    }

    var a2aConversations: [Conversation] {
        store.conversations.filter { $0.kind == .a2a }
                           .sorted { $0.lastTimestamp > $1.lastTimestamp }
    }

    var displayedConversations: [Conversation] {
        showSection == .user ? userConversations : a2aConversations
    }

    var body: some View {
        NavigationStack {
            Group {
                if !store.isConnected && !store.isConnecting {
                    notConnectedView
                } else if store.isConnecting || store.conversations.isEmpty {
                    connectingView
                } else {
                    conversationList
                }
            }
            .background(mcBg)
            .navigationTitle("消息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(item: $selectedConversation) { conv in
                ConversationDetailView(conversation: conv)
            }
        }
    }

    var conversationList: some View {
        VStack(spacing: 0) {
            // Section picker
            HStack(spacing: 0) {
                ForEach(ConversationSection.allCases, id: \.self) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showSection = section }
                    } label: {
                        VStack(spacing: 4) {
                            Text(section.rawValue)
                                .font(.system(size: 14, weight: showSection == section ? .semibold : .regular))
                                .foregroundStyle(showSection == section ? mcGreen : .white.opacity(0.4))
                            Rectangle()
                                .fill(showSection == section ? mcGreen : .clear)
                                .frame(height: 2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            if displayedConversations.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(displayedConversations) { conv in
                            ConversationRow(conversation: conv)
                                .onTapGesture { selectedConversation = conv }
                            Rectangle()
                                .fill(Color.white.opacity(0.04))
                                .frame(height: 1)
                                .padding(.leading, 72)
                        }
                    }
                }
            }
        }
    }

    var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.white.opacity(0.1))
            Text("暂无对话")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var connectingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(mcGreen)
            Text(store.isConnecting ? "连接中..." : "加载会话...")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(mcMint.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var notConnectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.white.opacity(0.15))
            Text("未连接 Gateway")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Text("前往设置页连接")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation

    var timeString: String {
        guard conversation.lastTimestamp > .distantPast else { return "" }
        let f = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(conversation.lastTimestamp) {
            f.dateFormat = "HH:mm"
        } else if cal.isDateInYesterday(conversation.lastTimestamp) {
            f.dateFormat = "昨天"
        } else {
            f.dateFormat = "M/d"
        }
        return f.string(from: conversation.lastTimestamp)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Avatar(s)
            if conversation.kind == .a2a {
                // Two avatars in a rounded square grid (like group chat)
                let cellSize: CGFloat = 20
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: conversation.color).opacity(0.15))
                            AvatarIcon(avatar: conversation.avatar, color: Color(hex: conversation.color), size: cellSize)
                        }
                        .frame(width: cellSize, height: cellSize)

                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.06))
                            AvatarIcon(avatar: conversation.secondaryAvatar, color: .white.opacity(0.5), size: cellSize)
                        }
                        .frame(width: cellSize, height: cellSize)
                    }
                }
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                .frame(width: 48, height: 48)
            } else {
                ZStack {
                    Circle()
                        .fill(Color(hex: conversation.color).opacity(0.15))
                        .frame(width: 48, height: 48)
                    AvatarIcon(avatar: conversation.avatar, color: Color(hex: conversation.color), size: 48)
                }
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if conversation.kind == .a2a {
                        // Show "A ↔ B"
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
                Text(conversation.lastMessageText.isEmpty ? "暂无消息" : conversation.lastMessageText)
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

// MARK: - Conversation Detail

struct ConversationDetailView: View {
    let conversation: Conversation
    @Environment(AppStore.self) var store
    @State private var inputText = ""
    @State private var isSending = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingImageData: Data?
    @State private var speechManager = SpeechManager()
    @State private var showCamera = false
    @State private var showFilePicker = false
    @FocusState private var isInputFocused: Bool

    var messages: [ChatMessage] {
        store.mountedMessages(for: conversation)
    }

    var canSend: Bool { conversation.kind == .user }

    var liveConversation: Conversation {
        store.conversations.first(where: { $0.id == conversation.id }) ?? conversation
    }

    var fullyMounted: Bool {
        store.isFullyMounted(for: liveConversation)
    }

    var streamingText: String? {
        store.agentStates[conversation.agentId]?.streamingText
    }

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty && !liveConversation.historyLoaded {
                VStack(spacing: 12) {
                    ProgressView().tint(mcGreen)
                    Text("加载中...")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if messages.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.white.opacity(0.1))
                    Text("暂无消息")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MessageListView(
                    messages: messages,
                    streamingText: streamingText,
                    agentAvatar: conversation.avatar,
                    fullyMounted: fullyMounted,
                    onMountMore: { store.mountMore(for: liveConversation) },
                    conversation: conversation
                )
            }

            if canSend {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                messageInput
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(mcBg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if conversation.kind == .a2a {
                    HStack(spacing: 4) {
                        Text(conversation.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("↔")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.3))
                        Text(conversation.secondaryName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                } else {
                    Text(conversation.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .task {
            if !liveConversation.historyLoaded {
                await store.fetchAllSessions(for: conversation)
            }
        }
    }

    var messageInput: some View {
        VStack(spacing: 0) {
            // Image preview
            if let data = pendingImageData, let uiImage = UIImage(data: data) {
                HStack(spacing: 8) {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Button { pendingImageData = nil; selectedPhoto = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.8))
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                        .offset(x: 4, y: -4)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            // Text field
            TextField("发消息...", text: $inputText, axis: .vertical)
                .focused($isInputFocused)
                .lineLimit(1...6)
                .font(.system(size: 15))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            // Toolbar row
            HStack(spacing: 8) {
                voiceButton

                if speechManager.isRecording {
                    Text(speechManager.transcript.isEmpty ? "正在听..." : speechManager.transcript)
                        .font(.system(size: 12))
                        .foregroundStyle(mcGreen.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()

                plusMenu

                if canSendNow {
                    Button { send() } label: {
                        Image(systemName: isSending ? "ellipsis" : "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(mcGreen)
                            .frame(width: 32, height: 32)
                    }
                    .disabled(isSending)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .onChange(of: selectedPhoto) {
            Task {
                if let data = try? await selectedPhoto?.loadTransferable(type: Data.self) {
                    pendingImageData = data
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { imageData in
                pendingImageData = imageData
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPicker { data, filename in
                // Send file as text with filename
                isSending = true
                let text = "[文件: \(filename)]"
                store.scrollPositions[conversation.id] = nil
                Task {
                    await store.sendMessage(sessionKey: conversation.sessionKey, agentId: conversation.agentId, text: text, imageData: data)
                    isSending = false
                }
            }
        }
    }

    @State private var showAttachSheet = false

    var plusMenu: some View {
        Button { showAttachSheet = true } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 32, height: 32)
        }
        .sheet(isPresented: $showAttachSheet) {
            AttachmentSheet(selectedPhoto: $selectedPhoto, onCamera: {
                showAttachSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showCamera = true }
            }, onFile: {
                showAttachSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showFilePicker = true }
            })
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(mcBg)
        }
    }

    var voiceButton: some View {
        Button {
            if speechManager.isRecording {
                speechManager.stop()
                if !speechManager.transcript.isEmpty {
                    inputText += speechManager.transcript
                }
            } else {
                speechManager.start()
            }
        } label: {
            Image(systemName: speechManager.isRecording ? "waveform.circle.fill" : "mic")
                .font(.system(size: 20))
                .foregroundStyle(speechManager.isRecording ? mcGreen : .white.opacity(0.4))
                .frame(width: 32, height: 32)
        }
    }

    var canSendNow: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingImageData != nil
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || pendingImageData != nil else { return }

        let imageData = pendingImageData.flatMap { compressImage($0, maxBytes: 4_500_000) }
        inputText = ""
        pendingImageData = nil
        selectedPhoto = nil
        isSending = true
        store.scrollPositions[conversation.id] = nil
        Task {
            await store.sendMessage(sessionKey: conversation.sessionKey, agentId: conversation.agentId, text: text, imageData: imageData)
            isSending = false
        }
    }

    private func compressImage(_ data: Data, maxBytes: Int) -> Data? {
        guard let uiImage = UIImage(data: data) else { return data }
        // If already small enough, use original
        if data.count <= maxBytes { return data }
        // Progressively reduce quality
        for quality in stride(from: 0.8, through: 0.1, by: -0.1) {
            if let compressed = uiImage.jpegData(compressionQuality: quality),
               compressed.count <= maxBytes {
                return compressed
            }
        }
        // Still too large — resize
        let scale = sqrt(Double(maxBytes) / Double(data.count))
        let newSize = CGSize(width: uiImage.size.width * scale, height: uiImage.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in uiImage.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: 0.7)
    }
}

// MARK: - Message List

// MARK: - Message List (pure SwiftUI)

struct MessageListView: View {
    let messages: [ChatMessage]
    let streamingText: String?
    let agentAvatar: String
    let fullyMounted: Bool
    let onMountMore: () -> Void
    var conversation: Conversation? = nil
    var savedScrollId: String? = nil
    var onScrollChanged: ((String?) -> Void)? = nil

    @State private var loadMoreTriggered = false
    @State private var didInitialScroll = false
    @State private var anchorBeforeLoad: String?
    @State private var lastMessageCount = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    // Load more trigger at top
                    if !fullyMounted && didInitialScroll {
                        ProgressView().tint(mcGreen)
                            .padding(.vertical, 8)
                            .onAppear {
                                guard !loadMoreTriggered else { return }
                                loadMoreTriggered = true
                                // Save the first message as anchor before loading
                                anchorBeforeLoad = messages.first?.id
                                onMountMore()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                    loadMoreTriggered = false
                                }
                            }
                    }

                    ForEach(groupedByDate, id: \.date) { group in
                        // Date header
                        Text(group.label)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)

                        ForEach(group.messages) { msg in
                            Group {
                                if let conv = conversation, conv.kind == .a2a {
                                    A2AMessageBubble(message: msg, conversation: conv)
                                } else {
                                    MessageBubble(message: msg, agentAvatar: agentAvatar)
                                }
                            }
                            .id(msg.id)
                        }
                    }

                    if let streaming = streamingText, !streaming.isEmpty {
                        StreamingBubble(text: streaming, avatar: agentAvatar)
                            .id("streaming")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                if !didInitialScroll {
                    lastMessageCount = messages.count
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let lastId = messages.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                        didInitialScroll = true
                    }
                }
            }
            .onChange(of: messages.count) { oldCount, newCount in
                if let anchor = anchorBeforeLoad, newCount > oldCount {
                    // Older messages were prepended — restore position
                    anchorBeforeLoad = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.none) {
                            proxy.scrollTo(anchor, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    // Group messages by date
    private var groupedByDate: [DateGroup] {
        let cal = Calendar.current
        var groups: [DateGroup] = []
        var currentDay: DateComponents?
        var currentMsgs: [ChatMessage] = []

        for msg in messages {
            let day = cal.dateComponents([.year, .month, .day], from: msg.timestamp)
            if day != currentDay {
                if !currentMsgs.isEmpty, let cd = currentDay {
                    groups.append(DateGroup(date: "\(cd.year!)-\(cd.month!)-\(cd.day!)",
                                           label: dateLabel(for: currentMsgs[0].timestamp),
                                           messages: currentMsgs))
                }
                currentDay = day
                currentMsgs = [msg]
            } else {
                currentMsgs.append(msg)
            }
        }
        if !currentMsgs.isEmpty, let cd = currentDay {
            groups.append(DateGroup(date: "\(cd.year!)-\(cd.month!)-\(cd.day!)",
                                   label: dateLabel(for: currentMsgs[0].timestamp),
                                   messages: currentMsgs))
        }
        return groups
    }

    private func dateLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh-Hans")
        f.dateFormat = cal.component(.year, from: date) == cal.component(.year, from: Date())
            ? "M月d日 EEEE" : "yyyy年M月d日 EEEE"
        return f.string(from: date)
    }

    struct DateGroup {
        let date: String
        let label: String
        let messages: [ChatMessage]
    }
}

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

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(message.timestamp) ? "HH:mm" : "M/d HH:mm"
        return f.string(from: message.timestamp)
    }

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

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    let agentAvatar: String

    var isUser: Bool { message.role == .user }

    var timeString: String {
        let f = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(message.timestamp) {
            f.dateFormat = "HH:mm"
        } else if cal.isDateInYesterday(message.timestamp) {
            f.dateFormat = "昨天 HH:mm"
        } else {
            f.dateFormat = "M/d HH:mm"
        }
        return f.string(from: message.timestamp)
    }

    @State private var fullscreenImage: UIImage? = nil

    // Extract text (without images) and images separately
    private var textOnly: String {
        let pattern = #"!\[[^\]]*\]\([^)]+\)|data:image\/[^;]+;base64,[A-Za-z0-9+/=\n]+"#
        let cleaned = (try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]))
            .map { $0.stringByReplacingMatches(in: message.text, range: NSRange(location: 0, length: (message.text as NSString).length), withTemplate: "") } ?? message.text
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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

                Text(timeString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
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

// MARK: - Rich Message Content (images + text)

struct MessageContentView: View {
    let text: String
    var localImageData: Data? = nil
    @State private var fullscreenImage: UIImage? = nil

    // Extract image URLs (markdown ![](url) or data:image/... URLs)
    private var parts: [(kind: PartKind, value: String)] {
        var result: [(kind: PartKind, value: String)] = []
        let pattern = #"!\[[^\]]*\]\(([^)]+)\)|(?:^|\n)(data:image\/[^;]+;base64,[A-Za-z0-9+/=\n]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return [(.text, text)]
        }

        var lastEnd = text.startIndex
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            let matchRange = Range(match.range, in: text)!
            // Text before this match
            if lastEnd < matchRange.lowerBound {
                let before = String(text[lastEnd..<matchRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !before.isEmpty { result.append((.text, before)) }
            }
            // Image URL
            if let urlRange = Range(match.range(at: 1), in: text) {
                result.append((.image, String(text[urlRange])))
            } else if let dataRange = Range(match.range(at: 2), in: text) {
                result.append((.image, String(text[dataRange])))
            }
            lastEnd = matchRange.upperBound
        }
        // Remaining text
        if lastEnd < text.endIndex {
            let remaining = String(text[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty { result.append((.text, remaining)) }
        }

        return result.isEmpty ? [(.text, text)] : result
    }

    enum PartKind { case text, image }

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
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            AsyncImage(url: URL(string: part.value)) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFit()
                                        .frame(maxWidth: 240)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
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

extension UIImage: @retroactive Identifiable {
    public var id: Int { hash }
}

// MARK: - Image Viewer (fullscreen, zoom, save)

struct ImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) var dismiss
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var showSaveToast = false
    @GestureState private var gestureScale: CGFloat = 1
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .onTapGesture { dismiss() }

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale * gestureScale)
                .offset(CGSize(
                    width: offset.width + dragOffset.width,
                    height: offset.height + dragOffset.height
                ))
                .gesture(
                    MagnifyGesture()
                        .updating($gestureScale) { value, state, _ in
                            state = value.magnification
                        }
                        .onEnded { value in
                            scale = max(scale * value.magnification, 1)
                            if scale <= 1 { offset = .zero }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in
                            if scale > 1 { state = value.translation }
                        }
                        .onEnded { value in
                            if scale > 1 {
                                offset.width += value.translation.width
                                offset.height += value.translation.height
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if scale > 1 { scale = 1; offset = .zero }
                        else { scale = 3 }
                    }
                }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                    }
                    Spacer()
                    Button {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                        showSaveToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showSaveToast = false }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }

            if showSaveToast {
                VStack {
                    Spacer()
                    Text("已保存到相册")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.white.opacity(0.2)))
                        .padding(.bottom, 60)
                }
            }
        }
    }
}

// MARK: - Selectable Text (UITextView wrapper for drag-to-select)

struct SelectableText: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        configure(tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        configure(tv)
    }

    private func configure(_ tv: UITextView) {
        if let data = text.data(using: .utf8),
           let nsAttr = try? NSAttributedString(markdown: data, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            let mutable = NSMutableAttributedString(attributedString: nsAttr)
            mutable.addAttribute(.foregroundColor, value: UIColor.white, range: NSRange(location: 0, length: mutable.length))
            mutable.addAttribute(.font, value: UIFont.systemFont(ofSize: fontSize), range: NSRange(location: 0, length: mutable.length))
            tv.attributedText = mutable
        } else {
            tv.text = text
            tv.textColor = .white
            tv.font = .systemFont(ofSize: fontSize)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let maxWidth = proposal.width ?? UIScreen.main.bounds.width - 80
        // Measure natural width first
        let natural = uiView.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        let width = min(natural.width, maxWidth)
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}

// MARK: - Attachment Sheet

struct AttachmentSheet: View {
    @Binding var selectedPhoto: PhotosPickerItem?
    var onCamera: () -> Void
    var onFile: () -> Void
    @Environment(\.dismiss) var dismiss

    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 24) {
            LazyVGrid(columns: columns, spacing: 16) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    attachItem(icon: "photo", label: "照片")
                }
                .onChange(of: selectedPhoto) { dismiss() }

                Button { onCamera() } label: {
                    attachItem(icon: "camera", label: "拍照")
                }

                Button { onFile() } label: {
                    attachItem(icon: "doc", label: "文件")
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
    }

    func attachItem(icon: String, label: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 70)
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

// MARK: - Speech Manager (Apple STT)

@Observable
class SpeechManager {
    var isRecording = false
    var transcript = ""

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
    }

    func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized else { return }
                self?.startRecording()
            }
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }

    private func startRecording() {
        transcript = ""
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()
        isRecording = true

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                if let result {
                    self?.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal == true) {
                    self?.stop()
                }
            }
        }
    }
}

// MARK: - Camera Picker

struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Document Picker

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (Data, String) -> Void
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url) {
                parent.onPick(data, url.lastPathComponent)
            }
            parent.dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}
