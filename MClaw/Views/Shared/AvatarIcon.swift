import SwiftUI

struct AvatarIcon: View {
    let avatar: String
    let color: Color
    let size: CGFloat

    private var isSFSymbol: Bool {
        !avatar.isEmpty && avatar.allSatisfy { $0.isASCII }
    }

    var body: some View {
        if isSFSymbol {
            Image(systemName: avatar)
                .font(.system(size: size * 0.45, weight: .light))
                .foregroundStyle(color)
        } else {
            Text(verbatim: avatar)
                .font(.system(size: size * 0.5))
        }
    }
}
