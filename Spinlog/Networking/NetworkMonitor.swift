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

    /// Permet de simuler un mode hors ligne à des fins de test et de débogage sans couper le Wi-Fi/4G.
    var simulatedOffline: Bool = false {
        didSet {
            guard simulatedOffline != oldValue else { return }
            if simulatedOffline {
                isConnected = false
            } else {
                isConnected = monitor.currentPath.status == .satisfied
                if isConnected {
                    NotificationCenter.default.post(name: .networkConnectionRestored, object: nil)
                }
            }
        }
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.spinlog.networkmonitor", qos: .background)

    private init() {
        // Pas de lecture de `monitor.currentPath` ici : avant `start()`, ce chemin n'est pas
        // encore évalué et peut se dire non satisfait, ce qui faisait démarrer l'app en "hors
        // ligne" (cache seul, bannière) jusqu'au premier `pathUpdateHandler`. On part donc de
        // l'hypothèse "connecté" ; le handler, appelé dès le démarrage, rétablit l'état réel en
        // quelques millisecondes (et une requête lancée entre-temps hors ligne retombe déjà sur
        // le cache local).

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.simulatedOffline {
                    self.isConnected = false
                    return
                }

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
