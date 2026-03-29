import SwiftUI

private let mcGreen = Theme.green
private let mcBg = Theme.bg
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
    @State private var readyForLoadMore = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 4) {
                    // Load more trigger at top
                    if !fullyMounted && readyForLoadMore {
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

                    // Invisible bottom anchor
                    Color.clear.frame(height: 1).id("__bottom__")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                if !didInitialScroll && !messages.isEmpty {
                    scrollToBottom(proxy)
                }
            }
            .onChange(of: messages.count) { oldCount, newCount in
                if !didInitialScroll && newCount > 0 {
                    scrollToBottom(proxy)
                }
                // New live message arrived — scroll to bottom
                if didInitialScroll && readyForLoadMore && newCount == oldCount + 1 {
                    proxy.scrollTo("__bottom__")
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

    private func dateLabel(for date: Date) -> String { formatDateSectionLabel(date) }

    struct DateGroup {
        let date: String
        let label: String
        let messages: [ChatMessage]
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        didInitialScroll = true
        // Defer to next run loop to ensure VStack layout is complete
        DispatchQueue.main.async {
            proxy.scrollTo("__bottom__")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            readyForLoadMore = true
        }
    }
}
