import SwiftUI
import PhotosUI
import Speech
import AVFoundation

private let mcGreen = Theme.green
private let mcMint  = Theme.mint
private let mcBg    = Theme.bg

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
                // Access store.messages.count to ensure re-render when messages load
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
