import Foundation
import Network

@Observable
final class NetworkMonitor {
    private(set) var isConnected = true
    private(set) var isCellular = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "clawmo.network-monitor")

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasConnected = self?.isConnected ?? true
                self?.isConnected = path.status == .satisfied
                self?.isCellular = path.usesInterfaceType(.cellular)

                if !wasConnected && path.status == .satisfied {
                    NSLog("[net] network restored")
                    NotificationCenter.default.post(name: .networkRestored, object: nil)
                } else if wasConnected && path.status != .satisfied {
                    NSLog("[net] network lost")
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}

extension Notification.Name {
    static let networkRestored = Notification.Name("clawmo.networkRestored")
}
