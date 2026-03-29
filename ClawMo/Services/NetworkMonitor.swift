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
            let satisfied = path.status == .satisfied
            let cellular = path.usesInterfaceType(.cellular)
            DispatchQueue.main.async {
                guard let self else { return }
                let wasConnected = self.isConnected
                self.isConnected = satisfied
                self.isCellular = cellular

                if !wasConnected && satisfied {
                    NSLog("[net] network restored")
                    NotificationCenter.default.post(name: .networkRestored, object: nil)
                } else if wasConnected && !satisfied {
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
