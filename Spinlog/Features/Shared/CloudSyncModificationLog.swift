import Foundation

/// Résolution des conflits iCloud : la modification la plus récente l'emporte.
///
/// Auparavant, en cas de conflit, la version de l'appareil qui envoyait en dernier gagnait
/// toujours — y compris une modification ancienne faite hors ligne, qui écrasait alors une
/// modification plus récente faite entre-temps sur un autre appareil.
///
/// Chaque modification locale encore en attente d'envoi est datée ici (par compte et par
/// enregistrement), et chaque enregistrement envoyé porte cette date dans le champ
/// `modifiedAt`. À la réception d'un changement distant, ou quand iCloud refuse un envoi parce
/// que le serveur a une autre version, les deux dates sont comparées.
enum CloudSyncModificationLog {
    /// Champ CloudKit portant la date de la modification à l'origine de l'enregistrement.
    nonisolated static let modifiedAtField = "modifiedAt"

    private static func storageKey(for username: String) -> String {
        "com.spinlog.cloudSync.localModifiedAt_\(username)"
    }

    private static func entries(for username: String, defaults: UserDefaults) -> [String: Double] {
        defaults.dictionary(forKey: storageKey(for: username)) as? [String: Double] ?? [:]
    }

    /// Date de la modification locale en attente d'envoi, `nil` s'il n'y en a pas.
    static func pendingDate(for recordName: String, username: String, defaults: UserDefaults = .standard) -> Date? {
        entries(for: username, defaults: defaults)[recordName].map(Date.init(timeIntervalSince1970:))
    }

    static func recordLocalModification(_ recordName: String, at date: Date = Date(), username: String, defaults: UserDefaults = .standard) {
        var all = entries(for: username, defaults: defaults)
        all[recordName] = date.timeIntervalSince1970
        defaults.set(all, forKey: storageKey(for: username))
    }

    /// La modification locale n'est plus en attente (envoyée, ou remplacée par une version
    /// distante plus récente). `onlyIfDatedAt` : n'efface que si aucune modification plus récente
    /// n'a été faite entre-temps (elle reste alors à envoyer, avec sa propre date).
    static func clear(_ recordName: String, onlyIfDatedAt date: Date? = nil, username: String, defaults: UserDefaults = .standard) {
        var all = entries(for: username, defaults: defaults)
        guard let current = all[recordName] else { return }
        if let date, abs(current - date.timeIntervalSince1970) > 0.001 { return }
        all[recordName] = nil
        defaults.set(all, forKey: storageKey(for: username))
    }

    static func clearAll(for username: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey(for: username))
    }

    /// Faut-il appliquer la version distante plutôt que garder la modification locale ?
    /// - Aucune modification locale en attente : oui, toujours (cas normal).
    /// - Version distante non datée (envoyée par une version antérieure de l'app) : non, on garde
    ///   la modification locale, comme avant.
    /// - Sinon, la plus récente des deux l'emporte (égalité : la version distante).
    nonisolated static func remoteWins(remoteModifiedAt: Date?, localPendingAt: Date?) -> Bool {
        guard let localPendingAt else { return true }
        guard let remoteModifiedAt else { return false }
        return remoteModifiedAt >= localPendingAt
    }
}
