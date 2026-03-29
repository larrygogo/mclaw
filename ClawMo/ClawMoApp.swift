import SwiftUI
import SwiftData

@main
struct ClawMoApp: App {
    @State private var store: AppStore
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([PersistedMessage.self])
        let config = ModelConfiguration("ClawMo", isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema changed — delete old store and retry
            let url = config.url
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("store-shm"))
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("store-wal"))
            do {
                modelContainer = try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Failed to create ModelContainer after reset: \(error)")
            }
        }

        let s = AppStore(modelContainer: modelContainer)
        if CommandLine.arguments.contains("-mock") {
            s.loadMockData()
        }
        if let gwIdx = CommandLine.arguments.firstIndex(of: "-gateway"),
           CommandLine.arguments.count > gwIdx + 2 {
            let url = CommandLine.arguments[gwIdx + 1]
            let token = CommandLine.arguments[gwIdx + 2]
            let gwConfig = GatewayConfig(name: "Gateway", url: url, token: token)
            s.addGateway(gwConfig)
            s.activeGatewayId = gwConfig.id
            UserDefaults.standard.set(gwConfig.id, forKey: "clawmo-active-gateway")
        }
        _store = State(initialValue: s)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
        .modelContainer(modelContainer)
    }
}
