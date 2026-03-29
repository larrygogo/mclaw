import SwiftUI
import UIKit

struct SelectableText: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.tag = 100
        container.addSubview(tv)

        tv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tv.topAnchor.constraint(equalTo: container.topAnchor),
            tv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            tv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        context.coordinator.textView = tv

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        container.addGestureRecognizer(longPress)

        configure(tv)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if let tv = container.viewWithTag(100) as? UITextView {
            configure(tv)
        }
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

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        guard let tv = uiView.viewWithTag(100) as? UITextView else { return nil }
        let maxWidth = proposal.width ?? UIScreen.main.bounds.width - 80
        let natural = tv.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        let width = min(natural.width, maxWidth)
        let size = tv.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    class Coordinator: NSObject {
        weak var textView: UITextView?
        private var dismissTap: UITapGestureRecognizer?

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let tv = textView else { return }
            tv.isSelectable = true
            tv.isUserInteractionEnabled = true
            tv.becomeFirstResponder()
            tv.selectAll(nil)
            addDismissTap()
        }

        private func addDismissTap() {
            guard let window = textView?.window, dismissTap == nil else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleOutsideTap(_:)))
            tap.cancelsTouchesInView = false
            window.addGestureRecognizer(tap)
            dismissTap = tap
        }

        @objc func handleOutsideTap(_ gesture: UITapGestureRecognizer) {
            guard let tv = textView else { return }
            let location = gesture.location(in: tv)
            if !tv.bounds.contains(location) {
                dismissSelection()
            }
        }

        func dismissSelection() {
            guard let tv = textView else { return }
            tv.selectedTextRange = nil
            tv.isSelectable = false
            tv.resignFirstResponder()
            if let tap = dismissTap {
                tap.view?.removeGestureRecognizer(tap)
                dismissTap = nil
            }
        }
    }
}
