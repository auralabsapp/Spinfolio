import Foundation
import Observation

/// Clés des réglages de rangement, propres à chaque compte Discogs. Auparavant globales : un
/// second compte héritait de la règle de tri et des personnalisations d'artistes du premier,
/// puis les poussait dans sa propre zone iCloud, et « Supprimer mes données » les laissait.
nonisolated struct ShelfPreferenceKeys {
    static let strategy = "com.spinlog.shelfSortStrategy"
    static let ignoreArticles = "com.spinlog.shelfIgnoreArticles"
    static let sortByLastName = "com.spinlog.shelfSortByLastName"
    static let restrictToSameFolder = "com.spinlog.shelfRestrictToSameFolder"
    static let customArtistOverrides = "com.spinlog.shelfCustomArtistOverrides"
    static let all = [strategy, ignoreArticles, sortByLastName, restrictToSameFolder, customArtistOverrides]

    let defaults: UserDefaults

    static func key(_ base: String, for username: String) -> String {
        "\(base)_\(username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    /// Réglages de la version précédente (clés globales) rattachés au premier compte qui les
    /// lit, sans jamais écraser une valeur déjà propre à ce compte, puis supprimés : un autre
    /// compte ne les reçoit pas.
    func migrateLegacyIfNeeded(to username: String) {
        for base in Self.all {
            guard let legacy = defaults.object(forKey: base) else { continue }
            let accountKey = Self.key(base, for: username)
            if defaults.object(forKey: accountKey) == nil {
                defaults.set(legacy, forKey: accountKey)
            }
            defaults.removeObject(forKey: base)
        }
    }

    func clear(for username: String) {
        for base in Self.all {
            defaults.removeObject(forKey: Self.key(base, for: username))
        }
    }
}

/// Gère la persistance et la réactivité des réglages de rangement du compte actif.
@Observable
@MainActor
final class ShelfPreferencesStore {
    static let shared = ShelfPreferencesStore()

    private let defaults: UserDefaults
    private var keys: ShelfPreferenceKeys { ShelfPreferenceKeys(defaults: defaults) }
    private(set) var activeUsername: String?

    var sortStrategy: ShelfSortStrategy = .artistThenMasterYear {
        didSet { didChange(ShelfPreferenceKeys.strategy, value: sortStrategy.rawValue) }
    }

    var ignoreArticles: Bool = true {
        didSet { didChange(ShelfPreferenceKeys.ignoreArticles, value: ignoreArticles) }
    }

    /// Trier les artistes solo par nom de famille (désactivé par défaut)
    var sortByLastName: Bool = false {
        didSet { didChange(ShelfPreferenceKeys.sortByLastName, value: sortByLastName) }
    }

    /// Restreint la recherche de voisins au seul dossier Discogs contenant le disque ciblé,
    /// plutôt qu'à toute la collection tous dossiers confondus (comportement par défaut, qui
    /// correspond à la réalité physique de la plupart des utilisateurs : les dossiers Discogs
    /// sont une organisation thématique, pas un découpage en meubles séparés). Utile seulement
    /// si l'utilisateur fait correspondre ses dossiers Discogs à des espaces de rangement
    /// physiquement distincts.
    var restrictToSameFolder: Bool = false {
        didSet { didChange(ShelfPreferenceKeys.restrictToSameFolder, value: restrictToSameFolder) }
    }

    /// Dictionnaire de surcharges manuelles : [NomArtisteOriginal: CléDeTri]
    var customArtistSortOverrides: [String: String] = [:] {
        didSet { didChange(ShelfPreferenceKeys.customArtistOverrides, value: customArtistSortOverrides) }
    }

    /// Empêche `applyRemoteShelfPreferences`/`applyRemoteCustomArtistSortOverrides` de
    /// redéclencher un envoi vers CloudKit : cette donnée en vient déjà (voir
    /// `TagStore.applyRemoteTags` pour le même besoin).
    private var isApplyingRemoteShelfPreferences = false
    /// Chargement des réglages d'un compte (`setActiveUsername`) : rien à réécrire ni à envoyer.
    private var isLoadingAccount = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func didChange(_ base: String, value: Any) {
        guard !isLoadingAccount else { return }
        // Sans compte (déconnecté), le réglage ne vaut que pour l'affichage en cours.
        if let activeUsername {
            defaults.set(value, forKey: ShelfPreferenceKeys.key(base, for: activeUsername))
        }
        NotificationCenter.default.post(name: .shelfPreferencesChanged, object: nil)
        if !isApplyingRemoteShelfPreferences {
            CloudSyncEngine.shared.markShelfPreferencesDirty()
        }
    }

    // MARK: - Compte actif

    /// Bascule sur les réglages du compte indiqué (valeurs par défaut sans compte) : appelé par
    /// `DiscogsAuthManager` aux mêmes points que `TagStore.setActiveUsername`.
    func setActiveUsername(_ username: String?) {
        let normalized = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let account = (normalized?.isEmpty == false) ? normalized : nil
        guard account != activeUsername else { return }
        activeUsername = account
        // La démo ne récupère jamais les réglages globaux d'avant la mise à jour.
        if let account, account != DemoMode.username.lowercased() {
            keys.migrateLegacyIfNeeded(to: account)
        }
        loadActiveAccount()
        NotificationCenter.default.post(name: .shelfPreferencesChanged, object: nil)
    }

    /// Suppression des données (ou sortie de la démo) : le compte repart des réglages par défaut.
    func clearAccountData(for username: String) {
        keys.clear(for: username)
        if activeUsername == username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            loadActiveAccount()
            NotificationCenter.default.post(name: .shelfPreferencesChanged, object: nil)
        }
    }

    private func loadActiveAccount() {
        isLoadingAccount = true
        defer { isLoadingAccount = false }
        func value(_ base: String) -> Any? {
            activeUsername.flatMap { defaults.object(forKey: ShelfPreferenceKeys.key(base, for: $0)) }
        }
        sortStrategy = (value(ShelfPreferenceKeys.strategy) as? String).flatMap(ShelfSortStrategy.init) ?? .artistThenMasterYear
        ignoreArticles = value(ShelfPreferenceKeys.ignoreArticles) as? Bool ?? true
        sortByLastName = value(ShelfPreferenceKeys.sortByLastName) as? Bool ?? false
        restrictToSameFolder = value(ShelfPreferenceKeys.restrictToSameFolder) as? Bool ?? false
        customArtistSortOverrides = value(ShelfPreferenceKeys.customArtistOverrides) as? [String: String] ?? [:]
    }

    // MARK: - iCloud et sauvegarde

    /// Applique un état de préférences de rangement reçu d'iCloud (dictionnaire de
    /// personnalisations déjà fusionné si besoin par `CloudSyncEngine`, voir sa logique de
    /// première synchro). N'écrit qu'en local.
    func applyRemoteShelfPreferences(
        sortStrategy: ShelfSortStrategy,
        ignoreArticles: Bool,
        sortByLastName: Bool,
        restrictToSameFolder: Bool,
        customArtistSortOverrides: [String: String]
    ) {
        isApplyingRemoteShelfPreferences = true
        self.sortStrategy = sortStrategy
        self.ignoreArticles = ignoreArticles
        self.sortByLastName = sortByLastName
        self.restrictToSameFolder = restrictToSameFolder
        self.customArtistSortOverrides = customArtistSortOverrides
        isApplyingRemoteShelfPreferences = false
    }

    /// Applique uniquement les personnalisations d'artistes (utilisé par la restauration de
    /// sauvegarde JSON, qui ne porte pas les 3 autres réglages). N'écrit qu'en local.
    func applyRemoteCustomArtistSortOverrides(_ overrides: [String: String]) {
        isApplyingRemoteShelfPreferences = true
        customArtistSortOverrides = overrides
        isApplyingRemoteShelfPreferences = false
    }

    // MARK: - Personnalisations d'artistes

    func setCustomSort(for artist: String, sortKey: String?) {
        let key = ArtistShelfSortHelper.cleanDiscogsSuffix(artist)
        if let sortKey = sortKey?.trimmingCharacters(in: .whitespacesAndNewlines), !sortKey.isEmpty {
            customArtistSortOverrides[key] = sortKey
        } else {
            customArtistSortOverrides.removeValue(forKey: key)
        }
    }

    func customSort(for artist: String) -> String? {
        let key = ArtistShelfSortHelper.cleanDiscogsSuffix(artist)
        return customArtistSortOverrides[key]
    }

    func resetAllOverrides() {
        customArtistSortOverrides = [:]
    }
}
