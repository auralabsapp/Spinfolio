import Foundation
import Network
import Observation

/// Surveille l'état de la connectivité réseau en temps réel via Network.framework (NWPathMonitor).
/// Expose l'état actuel (`isConnected: Bool`) et diffuse les transitions réseau à l'ensemble de l'UI.
@Observable
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isConnected: Bool = true
    private(set) var isExpensive: Bool = false
    private(set) var isConstrained: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.spinlog.networkmonitor", qos: .background)

    private init() {
        self.isConnected = monitor.currentPath.status == .satisfied
        self.isExpensive = monitor.currentPath.isExpensive
        self.isConstrained = monitor.currentPath.isConstrained

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let previousState = self.isConnected
                let newState = path.status == .satisfied
                self.isConnected = newState
                self.isExpensive = path.isExpensive
                self.isConstrained = path.isConstrained

                // Notification si la connexion réseau est rétablie
                if !previousState && newState {
                    NotificationCenter.default.post(name: .networkConnectionRestored, object: nil)
                }
            }
        }
        monitor.start(queue: queue)
    }
}

extension Notification.Name {
    static let networkConnectionRestored = Notification.Name("com.spinlog.networkConnectionRestored")
}
