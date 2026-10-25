import Foundation

/// Date de la dernière synchro hors ligne et nombre de disques archivés, rangés par compte : une
/// valeur unique pour tout l'appareil faisait sauter la synchro auto du compte suivant (« déjà faite
/// il y a moins de 6 h ») et affichait chez lui la date et le compteur du compte précédent.
/// `UserDefaults` injecté pour les tests.
nonisolated struct OfflineSyncRecordStore {
    let defaults: UserDefaults

    /// Anciennes clés communes à tout l'appareil (avant le rangement par compte).
    static let legacyDateKey = "com.spinlog.lastOfflineSyncDate"
    static let legacyCountKey = "com.spinlog.offlineItemCount"

    static func dateKey(for username: String) -> String {
        "\(legacyDateKey)_\(normalized(username))"
    }

    static func countKey(for username: String) -> String {
        "\(legacyCountKey)_\(normalized(username))"
    }

    private static func normalized(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func lastSyncDate(for username: String?) -> Date? {
        guard let username else { return nil }
        return defaults.object(forKey: Self.dateKey(for: username)) as? Date
    }

    func itemCount(for username: String?) -> Int {
        guard let username else { return 0 }
        return defaults.integer(forKey: Self.countKey(for: username))
    }

    func recordSync(at date: Date, itemCount: Int, for username: String) {
        defaults.set(date, forKey: Self.dateKey(for: username))
        defaults.set(itemCount, forKey: Self.countKey(for: username))
    }

    func clear(for username: String) {
        defaults.removeObject(forKey: Self.dateKey(for: username))
        defaults.removeObject(forKey: Self.countKey(for: username))
    }

    /// Mise à jour depuis la version à clé unique : l'ancienne valeur revient au premier compte qui
    /// la lit (le compte connecté au lancement), puis les anciennes clés disparaissent.
    func migrateLegacyIfNeeded(to username: String) {
        guard defaults.object(forKey: Self.legacyDateKey) != nil || defaults.object(forKey: Self.legacyCountKey) != nil else { return }
        if defaults.object(forKey: Self.dateKey(for: username)) == nil,
           let legacyDate = defaults.object(forKey: Self.legacyDateKey) as? Date {
            defaults.set(legacyDate, forKey: Self.dateKey(for: username))
            defaults.set(defaults.integer(forKey: Self.legacyCountKey), forKey: Self.countKey(for: username))
        }
        defaults.removeObject(forKey: Self.legacyDateKey)
        defaults.removeObject(forKey: Self.legacyCountKey)
    }
}
