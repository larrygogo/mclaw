import SwiftUI
import UIKit

/// UITextView-based selectable text — supports drag-to-select on agent message bubbles.
/// Optimized: only re-configures when text actually changes, caches attributed string.
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
        // Reduce selection handle lag
        tv.layoutManager.allowsNonContiguousLayout = true
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

    final class Coordinator {
        private var lastText: String?
        private var lastFontSize: CGFloat?

        func configure(_ tv: UITextView, text: String, fontSize: CGFloat) {
            // Skip re-configuration if text and font unchanged
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
    }
}
