import SwiftUI

enum Theme {
    // Primary accent — neon green
    static let green = Color(hex: "39ff14")
    static let mint  = Color(hex: "b6ffa8")
    static let bg    = Color(red: 12/255, green: 13/255, blue: 14/255)

    // Surface layers (based on RGB 18,20,22 card color)
    static let surface1 = Color(red: 18/255, green: 20/255, blue: 22/255)   // cards, rows
    static let surface2 = Color(red: 26/255, green: 28/255, blue: 30/255)   // elevated cards
    static let surface3 = Color(red: 34/255, green: 36/255, blue: 38/255)   // hover, active
    static let border   = Color(red: 40/255, green: 42/255, blue: 44/255)   // subtle borders

    // Corner radius
    static let radiusS: CGFloat  = 8    // tags, small elements
    static let radiusM: CGFloat  = 12   // cards, bubbles, buttons
    static let radiusL: CGFloat  = 16   // sheets, large cards
    static let radiusXL: CGFloat = 20   // input bar, modals

    // Text hierarchy
    static let textPrimary   = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary  = Color.white.opacity(0.30)

    static let greenPalette: [Color] = [
        Color(hex: "39ff14"), Color(hex: "32cd32"), Color(hex: "00ff41"),
        Color(hex: "0fff50"), Color(hex: "7fff00"), Color(hex: "76ff03"),
        Color(hex: "39ff14"), Color(hex: "00e676"), Color(hex: "69f0ae"),
        Color(hex: "b2ff59"),
    ]

    static let agentColors = ["#818cf8", "#a78bfa", "#39ff14", "#fbbf24", "#22d3ee",
                               "#fb923c", "#f472b6", "#c084fc", "#00e676", "#94a3b8"]
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
