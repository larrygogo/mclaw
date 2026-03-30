import SwiftUI

/// Selectable text using native SwiftUI text selection (no UITextView)
struct SelectableText: View {
    let text: String
    let fontSize: CGFloat

    var body: some View {
        BubbleTextView(text: text, fontSize: fontSize)
    }
}
