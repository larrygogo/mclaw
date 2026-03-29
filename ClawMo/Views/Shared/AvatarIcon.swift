import SwiftUI

extension Notification.Name {
    static let agentAvatarChanged = Notification.Name("agentAvatarChanged")
}

struct AvatarIcon: View {
    let avatar: String
    let color: Color
    let size: CGFloat
    var agentId: String? = nil

    @State private var refreshId = UUID()

    private var resolvedAvatar: String {
        _ = refreshId // force dependency
        if let id = agentId, let custom = UserDefaults.standard.string(forKey: "agent_avatar_\(id)") {
            return custom
        }
        return avatar
    }

    private var isSFSymbol: Bool {
        !resolvedAvatar.isEmpty && resolvedAvatar.allSatisfy { $0.isASCII }
    }

    var body: some View {
        Group {
            if isSFSymbol {
                Image(systemName: resolvedAvatar)
                    .font(.system(size: size * 0.45, weight: .light))
                    .foregroundStyle(color)
            } else {
                Text(verbatim: resolvedAvatar)
                    .font(.system(size: size * 0.5))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentAvatarChanged)) { _ in
            refreshId = UUID()
        }
    }
}
