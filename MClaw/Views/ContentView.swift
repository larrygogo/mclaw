import SwiftUI

private let mcGreen = Theme.green

struct ContentView: View {
    @Environment(AppStore.self) var store
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            OfficeView()
                .tag(0)
                .tabItem {
                    TabIcon(name: "办公室", icon: "circle.grid.2x2", selected: selectedTab == 0)
                }

            MessageCenterView()
                .tag(1)
                .tabItem {
                    TabIcon(name: "消息", icon: "bubble.left.and.bubble.right", selected: selectedTab == 1)
                }

            SettingsView()
                .tag(2)
                .tabItem {
                    TabIcon(name: "设置", icon: "slider.horizontal.3", selected: selectedTab == 2)
                }
        }
        .tint(mcGreen)
        .task {
            if !store.isMockMode {
                store.loadCachedMessages()
                if let active = store.gateways.first(where: { $0.id == store.activeGatewayId }) {
                    await store.connect(to: active)
                }
            }
        }
    }
}

struct TabIcon: View {
    let name: String
    let icon: String
    let selected: Bool

    var body: some View {
        Label {
            Text(name)
        } icon: {
            Image(systemName: icon)
                .environment(\.symbolVariants, .none)
        }
    }
}
