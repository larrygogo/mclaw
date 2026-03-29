import SwiftUI
import UIKit

// MARK: - POC: UITableView-based message list
// Goal: verify 3 things:
// 1. Bottom anchoring on load (no visible scroll)
// 2. Prepend without jump (targetContentOffset)
// 3. Text selection works (native UIKit coordinates)

struct ChatTableView: UIViewRepresentable {
    let messages: [ChatMessage]
    let agentAvatar: String
    var conversation: Conversation? = nil
    let fullyMounted: Bool
    let onMountMore: () -> Void
    var onRetry: ((ChatMessage) -> Void)? = nil
    var savedOffset: CGFloat?
    var onOffsetChanged: ((CGFloat) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITableView {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.backgroundColor = .clear
        tv.separatorStyle = .none
        tv.keyboardDismissMode = .interactive
        tv.allowsSelection = false
        tv.estimatedRowHeight = 80
        tv.rowHeight = UITableView.automaticDimension
        tv.transform = CGAffineTransform(scaleX: 1, y: -1) // flip table
        tv.dataSource = context.coordinator
        tv.delegate = context.coordinator
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "msg")
        // In flipped table, headerView = visual bottom spacing
        let spacer = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 16))
        tv.tableHeaderView = spacer
        context.coordinator.tableView = tv
        context.coordinator.savedOffset = savedOffset

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        tv.addGestureRecognizer(tap)

        return tv
    }

    func updateUIView(_ tv: UITableView, context: Context) {
        let coord = context.coordinator
        coord.parent = self
        coord.rebuildItems()
        tv.reloadData()

        // Few messages: push content to visual top
        tv.layoutIfNeeded()
        let contentH = tv.contentSize.height
        let frameH = tv.frame.height
        if contentH < frameH {
            tv.contentInset.top = frameH - contentH
        } else {
            tv.contentInset.top = 0
        }

        // Restore saved scroll position (once)
        context.coordinator.restoreOffsetIfNeeded(tv)
    }

    // MARK: - Data items

    struct Item {
        let message: ChatMessage
        var dateHeader: String? = nil  // shown above this message if it's the first of its day
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate {
        var parent: ChatTableView
        var items: [Item] = []
        weak var tableView: UITableView?
        private var loadMoreTriggered = false
        internal var savedOffset: CGFloat?
        internal var didRestoreOffset = false

        init(parent: ChatTableView) {
            self.parent = parent
            super.init()
            rebuildItems()
        }

        func restoreOffsetIfNeeded(_ tv: UITableView) {
            guard !didRestoreOffset, let offset = savedOffset else { return }
            didRestoreOffset = true
            tv.contentOffset.y = offset
        }

        func rebuildItems() {
            // Build chronologically, attach date headers to first message of each day, then reverse
            var chronological: [Item] = []
            let cal = Calendar.current
            var currentDay: DateComponents?

            for msg in parent.messages {
                let day = cal.dateComponents([.year, .month, .day], from: msg.timestamp)
                var item = Item(message: msg)
                if day != currentDay {
                    item.dateHeader = formatDateSectionLabel(msg.timestamp)
                    currentDay = day
                }
                chronological.append(item)
            }
            items = chronological.reversed()
        }

        // MARK: - DataSource

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            items.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let item = items[indexPath.row]
            let msg = item.message
            let cell = tableView.dequeueReusableCell(withIdentifier: "msg", for: indexPath)
            cell.backgroundColor = .clear
            cell.selectionStyle = .none
            cell.transform = CGAffineTransform(scaleX: 1, y: -1)

            let isA2A = parent.conversation?.kind == .a2a
            let senderName: String? = isA2A ? (msg.role == .user ? parent.conversation?.displayName : parent.conversation?.secondaryName) : nil
            let dateLabel = item.dateHeader

            cell.contentConfiguration = UIHostingConfiguration {
                VStack(spacing: 0) {
                    MessageBubble(
                        message: msg,
                        agentAvatar: parent.agentAvatar,
                        agentId: parent.conversation?.agentId,
                        senderName: senderName,
                        onRetry: msg.sendStatus == .failed ? { [weak self] in self?.parent.onRetry?(msg) } : nil
                    )
                    // In flipped table: below message = visually above
                    if let dateLabel {
                        Text(dateLabel)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
            }
            .margins(.horizontal, 14)
            .margins(.vertical, 2)
            .background(.clear)

            return cell
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc func handleTap() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            parent.onOffsetChanged?(scrollView.contentOffset.y)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                parent.onOffsetChanged?(scrollView.contentOffset.y)
            }
        }

        // MARK: - Delegate (load more)

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // In flipped table, "bottom" of content = oldest messages
            let contentHeight = scrollView.contentSize.height
            let offset = scrollView.contentOffset.y
            let frameHeight = scrollView.frame.height

            // Near the bottom of flipped content = near oldest messages
            if offset + frameHeight > contentHeight - 200,
               !parent.fullyMounted,
               !loadMoreTriggered {
                loadMoreTriggered = true
                parent.onMountMore()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.loadMoreTriggered = false
                }
            }
        }
    }
}
