import SwiftUI
import UIKit

/// UITextView-based selectable text — supports drag-to-select on agent message bubbles
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
        let screenWidth = (uiView.window?.windowScene?.screen.bounds.width) ?? 375
        let maxWidth = proposal.width ?? screenWidth - 80
        let natural = uiView.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        let width = min(natural.width, maxWidth)
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}
