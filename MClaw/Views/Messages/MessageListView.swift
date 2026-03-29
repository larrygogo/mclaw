import SwiftUI

private let mcGreen = Theme.green
private let mcBg = Theme.bg

struct MessageListView: View {
    let messages: [ChatMessage]
    let streamingText: String?
    let agentAvatar: String
    let fullyMounted: Bool
    let onMountMore: () -> Void
    var conversation: Conversation? = nil

    @State private var loadMoreTriggered = false
    @State private var hasContent = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    // Load more — only fires when user scrolls to top (LazyVStack)
                    if !fullyMounted {
                        ProgressView().tint(mcGreen)
                            .padding(.vertical, 8)
                            .onAppear {
                                guard !loadMoreTriggered else { return }
                                loadMoreTriggered = true
                                onMountMore()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                    loadMoreTriggered = false
                                }
                            }
                    }

                    ForEach(groupedByDate, id: \.date) { group in
                        Text(group.label)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)

                        ForEach(group.messages) { msg in
                            MessageBubble(
                                message: msg,
                                agentAvatar: agentAvatar,
                                senderName: a2aName(for: msg)
                            )
                            .id(msg.id)
                        }
                    }

                    if let streaming = streamingText, !streaming.isEmpty {
                        StreamingBubble(text: streaming, avatar: agentAvatar)
                            .id("streaming")
                    }

                    Color.clear.frame(height: 1).id("__bottom__")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { oldCount, newCount in
                if !hasContent && newCount > 0 {
                    // First data arrived after empty render — scroll to bottom
                    hasContent = true
                    DispatchQueue.main.async {
                        proxy.scrollTo("__bottom__")
                    }
                } else if hasContent && newCount == oldCount + 1 {
                    // New live message — scroll to bottom
                    DispatchQueue.main.async {
                        proxy.scrollTo("__bottom__")
                    }
                }
            }
            .onAppear {
                if !messages.isEmpty {
                    hasContent = true
                    DispatchQueue.main.async {
                        proxy.scrollTo("__bottom__")
                    }
                }
            }
        }
    }

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
                                           label: formatDateSectionLabel(currentMsgs[0].timestamp),
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
                                   label: formatDateSectionLabel(currentMsgs[0].timestamp),
                                   messages: currentMsgs))
        }
        return groups
    }

    /// Returns agent name for A2A conversations, nil for regular
    private func a2aName(for msg: ChatMessage) -> String? {
        guard let conv = conversation, conv.kind == .a2a else { return nil }
        return msg.role == .user ? conv.displayName : conv.secondaryName
    }

    struct DateGroup {
        let date: String
        let label: String
        let messages: [ChatMessage]
    }
}
