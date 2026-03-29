import SwiftUI
import UIKit

struct SelectableText: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SelectableTextView {
        let tv = SelectableTextView()
        tv.isEditable = false
        tv.isSelectable = false // disabled until long press
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.coordinator = context.coordinator
        context.coordinator.textView = tv

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        tv.addGestureRecognizer(longPress)

        configure(tv)
        return tv
    }

    func updateUIView(_ tv: SelectableTextView, context: Context) {
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

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SelectableTextView, context: Context) -> CGSize? {
        let maxWidth = proposal.width ?? UIScreen.main.bounds.width - 80
        let natural = uiView.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        let width = min(natural.width, maxWidth)
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        weak var textView: SelectableTextView?

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let tv = textView else { return }
            tv.isSelectable = true
            tv.becomeFirstResponder()
            tv.selectAll(nil)
        }

        func deactivateSelection() {
            guard let tv = textView else { return }
            tv.selectedTextRange = nil
            tv.isSelectable = false
            tv.resignFirstResponder()
        }
    }
}

// MARK: - Custom UITextView that deactivates selection on outside tap

class SelectableTextView: UITextView {
    weak var coordinator: SelectableText.Coordinator?

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        // When losing focus (tap outside), deactivate selection
        DispatchQueue.main.async { [weak self] in
            self?.coordinator?.deactivateSelection()
        }
        return result
    }
}
