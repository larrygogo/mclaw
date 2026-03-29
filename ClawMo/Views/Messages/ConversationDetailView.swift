import SwiftUI
import PhotosUI

private let mcGreen = Theme.green
private let mcBg = Theme.bg

struct ConversationDetailView: View {
    let conversation: Conversation
    @Environment(AppStore.self) var store
    @State private var isSending = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var pendingImages: [Data] = []
    @State private var speechManager = SpeechManager()
    @State private var showCamera = false
    @State private var showFilePicker = false
    @FocusState private var isInputFocused: Bool

    private var inputText: Binding<String> {
        Binding(
            get: { store.draftTexts[conversation.id] ?? "" },
            set: { store.draftTexts[conversation.id] = $0 }
        )
    }

    private var inputTextValue: String { store.draftTexts[conversation.id] ?? "" }

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
                // POC: UITableView-based list for smooth scrolling
                ChatTableView(
                    messages: messages,
                    agentAvatar: conversation.kind == .a2a ? conversation.secondaryAvatar : conversation.avatar,
                    conversation: conversation,
                    fullyMounted: fullyMounted,
                    onMountMore: { store.mountMore(for: liveConversation) },
                    onRetry: { msg in Task { await store.retryMessage(msg) } },
                    savedOffset: store.scrollOffsets[conversation.id],
                    onOffsetChanged: { store.scrollOffsets[conversation.id] = $0 }
                )
            }

            if canSend {
                messageInput
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(mcBg)
        .toolbar(.hidden, for: .tabBar)
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
            // Image previews
            if !pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingImages.indices, id: \.self) { i in
                            if let uiImage = UIImage(data: pendingImages[i]) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))
                                    Button { pendingImages.remove(at: i) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(.white.opacity(0.8))
                                            .background(Circle().fill(Color.black.opacity(0.5)))
                                    }
                                    .offset(x: 4, y: -4)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            // TextField always exists (pre-loaded for instant focus)
            TextField("发消息...", text: inputText, axis: .vertical)
                .focused($isInputFocused)
                .lineLimit(1...6)
                .font(.system(size: 15))
                .padding(.horizontal, 16)
                .padding(.vertical, isExpanded ? 10 : 0)
                .frame(height: isExpanded ? nil : 0)
                .clipped()
                .onChange(of: isInputFocused) {
                    if !isInputFocused && inputTextValue.isEmpty && pendingImages.isEmpty {
                        inputExpanded = false
                    }
                }

            if isExpanded {
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
            } else {
                HStack(spacing: 8) {
                    voiceButton

                    Button {
                        inputExpanded = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isInputFocused = true
                        }
                    } label: {
                        Text("发消息...")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.3))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    plusMenu
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusXL)
                .fill(Theme.surface2)
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .onChange(of: selectedPhotos) {
            Task {
                for item in selectedPhotos {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        pendingImages.append(data)
                    }
                }
                selectedPhotos = []
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { imageData in
                pendingImages.append(imageData)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPicker { data, filename in
                isSending = true
                let text = "[文件: \(filename)]"
                store.scrollPositions[conversation.id] = nil
                Task {
                    await store.sendMessage(sessionKey: conversation.sessionKey, agentId: conversation.agentId, text: text, imageData: data, fileSize: Int64(data.count))
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
            AttachmentSheet(selectedPhotos: $selectedPhotos, onCamera: {
                showAttachSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showCamera = true }
            }, onFile: {
                showAttachSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showFilePicker = true }
            })
            .presentationDetents([.height(180)])
            .presentationDragIndicator(.visible)
            .presentationBackground(mcBg)
        }
    }

    var voiceButton: some View {
        Button {
            if speechManager.isRecording {
                speechManager.stop()
                if !speechManager.transcript.isEmpty {
                    store.draftTexts[conversation.id, default: ""] += speechManager.transcript
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

    @State private var inputExpanded = false

    private var isExpanded: Bool {
        inputExpanded || !inputTextValue.isEmpty || !pendingImages.isEmpty
    }

    var canSendNow: Bool {
        !inputTextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty
    }

    private func send() {
        let text = inputTextValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingImages.isEmpty else { return }

        // Compress first image (gateway supports one attachment per message)
        let imageData = pendingImages.first.flatMap { compressImage($0, maxBytes: 4_500_000) }
        let extraImages = pendingImages.dropFirst().map { compressImage($0, maxBytes: 4_500_000) }
        store.draftTexts[conversation.id] = ""
        pendingImages = []
        selectedPhotos = []
        isSending = true
        store.scrollPositions[conversation.id] = nil
        Task {
            // Send first image with text
            await store.sendMessage(sessionKey: conversation.sessionKey, agentId: conversation.agentId, text: text, imageData: imageData)
            // Send remaining images as separate messages
            for extra in extraImages {
                if let data = extra {
                    await store.sendMessage(sessionKey: conversation.sessionKey, agentId: conversation.agentId, text: "", imageData: data)
                }
            }
            isSending = false
        }
    }

}

