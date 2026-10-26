import Foundation

/// Pont de données entre l'app et l'extension de widgets (App Group partagé) : l'app y écrit
/// un instantané léger de la collection à chaque synchronisation complète, et le widget
/// "Album du jour" le relit pour piocher une pochette sans accès réseau ni au cache SwiftData
/// de l'app. Le tirage du jour est calculé à partir d'un hash stable de la date plutôt que
/// stocké, pour éviter tout aller-retour d'écriture depuis l'extension.
enum WidgetSnapshotStore {
    private static let collectionKey = SharedAppGroup.collectionSnapshotKey
    private static let isPremiumKey = SharedAppGroup.isPremiumKey
    private static let themeAccentKey = SharedAppGroup.themeAccentOnDarkKey
    private static let themeAccentOnLightKey = SharedAppGroup.themeAccentOnLightKey

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.id) ?? .standard
    }

    /// Nombre de disques de l'instantané, gardé en mémoire après la première lecture : la synchro
    /// de fond le consulte à chaque page reçue, et le décodage complet du JSON était refait à
    /// chaque fois. Seule l'app écrit l'instantané (via `saveCollection`), qui tient ce compteur à jour.
    private static var cachedCollectionCount: Int?

    static var collectionCount: Int {
        if let cachedCollectionCount { return cachedCollectionCount }
        let count = loadCollection().count
        cachedCollectionCount = count
        return count
    }

    static func saveCollection(_ items: [RandomAlbumSnapshotItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: collectionKey)
        cachedCollectionCount = items.count
    }

    static func loadCollection() -> [RandomAlbumSnapshotItem] {
        guard let data = defaults.data(forKey: collectionKey),
              let items = try? JSONDecoder().decode([RandomAlbumSnapshotItem].self, from: data) else {
            return []
        }
        return items
    }

    static var isPremium: Bool {
        defaults.bool(forKey: isPremiumKey)
    }

    static var hasReceivedDataFromApp: Bool {
        defaults.object(forKey: collectionKey) != nil || defaults.object(forKey: isPremiumKey) != nil
    }

    /// Couleur du thème transmise à l'extension (Live Activity, widget « Album du jour »), qui n'a
    /// pas accès au thème de l'app : variante pour fond sombre et variante foncée pour fond clair,
    /// lues par la copie de ce fichier côté extension. Composantes RGB entre 0 et 1.
    static func saveThemeAccents(onDark: [Double], onLight: [Double]) {
        defaults.set(onDark, forKey: themeAccentKey)
        defaults.set(onLight, forKey: themeAccentOnLightKey)
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
        // Masque plutôt que `abs` : `abs(Int.min)` fait planter le programme.
        return hash & Int.max
    }
}
