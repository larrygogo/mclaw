import SwiftUI

enum Theme {
    static let green = Color(hex: "39ff14")
    static let mint  = Color(hex: "b6ffa8")
    static let bg    = Color(hex: "0a0a0f")

    static let greenPalette: [Color] = [
        Color(hex: "39ff14"), Color(hex: "32cd32"), Color(hex: "00ff41"),
        Color(hex: "0fff50"), Color(hex: "7fff00"), Color(hex: "76ff03"),
        Color(hex: "39ff14"), Color(hex: "00e676"), Color(hex: "69f0ae"),
        Color(hex: "b2ff59"),
    ]

    static let agentColors = ["#6c5ce7", "#a29bfe", "#00e676", "#ffd600", "#18ffff",
                               "#ff7043", "#ec407a", "#ab47bc", "#26a69a", "#78909c"]
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
