import SwiftUI
import PhotosUI

private let mcGreen = Theme.green
private let mcBg = Theme.bg

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
                // POC: UITableView-based list for smooth scrolling
                ChatTableView(
                    messages: messages,
                    agentAvatar: conversation.kind == .a2a ? conversation.secondaryAvatar : conversation.avatar,
                    conversation: conversation,
                    fullyMounted: fullyMounted,
                    onMountMore: { store.mountMore(for: liveConversation) },
                    onRetry: { msg in Task { await store.retryMessage(msg) } }
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

}

