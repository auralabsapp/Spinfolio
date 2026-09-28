import Foundation

/// Un disque de la collection, réduit aux seules données nécessaires à l'affichage du widget
/// (pas de dépendance au cache SwiftData complet, invisible depuis l'extension de widgets).
struct RandomAlbumSnapshotItem: Codable, Sendable {
    let releaseId: Int
    let title: String
    let artistNames: String
    let coverURL: String?
}

/// Pont de données entre l'app et l'extension de widgets (App Group partagé) : l'app y écrit
/// un instantané léger de la collection à chaque synchronisation complète, et le widget
/// "Album du jour" le relit pour piocher une pochette sans accès réseau ni au cache SwiftData
/// de l'app. Le tirage du jour est calculé à partir d'un hash stable de la date plutôt que
/// stocké, pour éviter tout aller-retour d'écriture depuis l'extension.
enum WidgetSnapshotStore {
    private static let appGroupID = "group.com.aurelienscarpa.Spinlog"
    private static let collectionKey = "com.spinlog.widgetCollectionSnapshot"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func saveCollection(_ items: [RandomAlbumSnapshotItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: collectionKey)
    }

    static func loadCollection() -> [RandomAlbumSnapshotItem] {
        guard let data = defaults.data(forKey: collectionKey),
              let items = try? JSONDecoder().decode([RandomAlbumSnapshotItem].self, from: data) else {
            return []
        }
        return items
    }

    /// Choix stable pour une journée donnée : même date + même liste => même résultat.
    static func randomAlbum(for date: Date = Date(), from items: [RandomAlbumSnapshotItem]? = nil) -> RandomAlbumSnapshotItem? {
        let pool = items ?? loadCollection()
        guard !pool.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let dayString = formatter.string(from: date)
        let index = stableHash(dayString) % pool.count
        return pool[index]
    }

    /// Hash volontairement maison (djb2) : `Hasher`/`hashValue` de Swift sont salés
    /// aléatoirement par processus pour se protéger des attaques par hash-flooding, donc le
    /// même jour donnerait un résultat différent entre l'app et le widget (ou entre deux
    /// lancements de l'extension) si on s'y appuyait.
    private static func stableHash(_ string: String) -> Int {
        var hash = 5381
        for byte in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        return abs(hash)
    }
}
