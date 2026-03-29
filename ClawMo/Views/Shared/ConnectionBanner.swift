import SwiftUI

struct ConnectionBanner: View {
    @Environment(AppStore.self) var store

    var body: some View {
        if !store.networkMonitor.isConnected {
            banner(icon: "wifi.slash", text: "网络未连接", color: .red)
        } else if !store.isConnected && !store.isConnecting {
            banner(icon: "bolt.slash", text: "Gateway 已断开，重连中...", color: .orange)
        }
    }

    private func banner(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 12, design: .monospaced))
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
    }
}
