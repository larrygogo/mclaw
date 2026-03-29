import Foundation
import SwiftData

final class PersistenceService {
    private let modelContainer: ModelContainer?

    init(modelContainer: ModelContainer?) {
        self.modelContainer = modelContainer
    }

    @MainActor
    func loadCachedMessages(gatewayId: String) -> [ChatMessage] {
        guard let container = modelContainer, !gatewayId.isEmpty else { return [] }
        let gwId = gatewayId
        let context = container.mainContext
        var descriptor = FetchDescriptor<PersistedMessage>(
            predicate: #Predicate { $0.gatewayId == gwId },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 2000
        guard let persisted = try? context.fetch(descriptor) else { return [] }
        return persisted.reversed().map { $0.toChatMessage() }
    }

    func persistMessages(_ messages: [ChatMessage], gatewayId: String) {
        guard let container = modelContainer, !messages.isEmpty, !gatewayId.isEmpty else { return }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        for msg in messages {
            context.insert(PersistedMessage(from: msg, gatewayId: gatewayId))
        }
        try? context.save()
    }

    func getCacheSize() -> String {
        guard let container = modelContainer else { return "0" }
        let context = container.mainContext
        let count = (try? context.fetchCount(FetchDescriptor<PersistedMessage>())) ?? 0
        if count == 0 { return "无缓存" }
        let config = ModelConfiguration("ClawMo")
        let url = config.url
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let sizeMB = Double(fileSize) / 1_000_000
        if sizeMB >= 1 {
            return String(format: "%d 条 / %.1fMB", count, sizeMB)
        }
        return String(format: "%d 条 / %.0fKB", count, Double(fileSize) / 1000)
    }

    func clearPersistedMessages() {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        do {
            try context.delete(model: PersistedMessage.self)
            try context.save()
        } catch {
            NSLog("[persistence] clearCache error: %@", "\(error)")
        }
    }
}
