import Foundation

/// Délai minimal entre deux rechargements automatiques d'un écran depuis Discogs (apparition de
/// l'onglet) : sans lui, chaque retour sur Collection, Wantlist ou Stats relançait toutes les
/// requêtes, et une grosse collection pouvait ne jamais finir sa relecture de fond. Le
/// tirer-pour-actualiser, le retour du réseau et un changement de compte n'y sont pas soumis.
nonisolated struct ReloadThrottle: Sendable {
    static let minimumInterval: TimeInterval = 5 * 60

    private var lastReload: Date?
    private var username: String?

    /// Rechargement automatique permis : jamais fait, autre compte, ou dernier il y a plus de 5 min.
    func shouldReload(for username: String, now: Date = Date()) -> Bool {
        guard let lastReload, self.username == username else { return true }
        return now.timeIntervalSince(lastReload) >= Self.minimumInterval
    }

    mutating func recordReload(for username: String, at date: Date = Date()) {
        self.username = username
        lastReload = date
    }

    mutating func reset() {
        lastReload = nil
        username = nil
    }
}
