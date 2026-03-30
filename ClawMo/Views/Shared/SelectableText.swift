import SwiftUI
import UIKit

/// UITextView-based selectable text — supports drag-to-select on agent message bubbles.
/// Long press immediately shows selection handles without requiring finger lift.
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
        tv.layoutManager.allowsNonContiguousLayout = true

        // Add custom long-press to select word at touch point immediately
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.3
        longPress.delegate = context.coordinator
        tv.addGestureRecognizer(longPress)

        context.coordinator.configure(tv, text: text, fontSize: fontSize)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.configure(tv, text: text, fontSize: fontSize)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let maxWidth = proposal.width ?? (UIScreen.main.bounds.width - 80)
        let size = uiView.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: min(size.width, maxWidth), height: size.height)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var lastText: String?
        private var lastFontSize: CGFloat?

        func configure(_ tv: UITextView, text: String, fontSize: CGFloat) {
            guard text != lastText || fontSize != lastFontSize else { return }
            lastText = text
            lastFontSize = fontSize

            let font = UIFont.systemFont(ofSize: fontSize)
            if let data = text.data(using: .utf8),
               let nsAttr = try? NSAttributedString(
                   markdown: data,
                   options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
               ) {
                let mutable = NSMutableAttributedString(attributedString: nsAttr)
                let range = NSRange(location: 0, length: mutable.length)
                mutable.addAttribute(.foregroundColor, value: UIColor.white, range: range)
                mutable.addAttribute(.font, value: font, range: range)
                tv.attributedText = mutable
            } else {
                tv.text = text
                tv.textColor = .white
                tv.font = font
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let tv = gesture.view as? UITextView else { return }

            let point = gesture.location(in: tv)
            let charIndex = tv.layoutManager.characterIndex(
                for: point,
                in: tv.textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )

            guard charIndex < tv.textStorage.length else { return }

            // Select the word at touch point
            let wordRange = tv.tokenizer.rangeEnclosingPosition(
                tv.position(from: tv.beginningOfDocument, offset: charIndex)!,
                with: .word,
                inDirection: UITextDirection(rawValue: UITextStorageDirection.forward.rawValue)
            )

            if let range = wordRange {
                tv.selectedTextRange = range
            } else {
                // Fallback: select character at point
                if let start = tv.position(from: tv.beginningOfDocument, offset: charIndex),
                   let end = tv.position(from: start, offset: 1) {
                    tv.selectedTextRange = tv.textRange(from: start, to: end)
                }
            }

            Haptics.light()
        }

        // Allow our long press to work alongside UITextView's built-in gestures
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
