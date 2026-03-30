import UIKit

enum Haptics {
    private static let light_ = UIImpactFeedbackGenerator(style: .light)
    private static let medium_ = UIImpactFeedbackGenerator(style: .medium)
    private static let selection_ = UISelectionFeedbackGenerator()
    private static let notification_ = UINotificationFeedbackGenerator()

    /// Call once at launch to pre-arm the haptic engines
    static func warmup() {
        light_.prepare()
        medium_.prepare()
        selection_.prepare()
        notification_.prepare()
    }

    static func light() {
        light_.impactOccurred()
        light_.prepare()  // re-arm for next use
    }

    static func medium() {
        medium_.impactOccurred()
        medium_.prepare()
    }

    static func selection() {
        selection_.selectionChanged()
        selection_.prepare()
    }

    static func success() {
        notification_.notificationOccurred(.success)
        notification_.prepare()
    }

    static func error() {
        notification_.notificationOccurred(.error)
        notification_.prepare()
    }
}
