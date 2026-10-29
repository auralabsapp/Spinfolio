import Foundation

extension Notification.Name {
    static let collectionPreferencesChanged = Notification.Name("com.spinlog.collectionPreferencesChanged")
    static let lastConsultedFolderChanged = Notification.Name("com.spinlog.lastConsultedFolderChanged")
    /// Tri de la Wantlist modifié depuis iCloud (un autre appareil) : `WantlistViewModel` le réapplique.
    static let wantlistPreferencesChanged = Notification.Name("com.spinlog.wantlistPreferencesChanged")
}

/// Gère la mémorisation et la persistance des préférences de collection par utilisateur :
/// - Dernier dossier consulté
/// - Critère de tri sélectionné (CollectionSortOption)
/// - Critères de filtre (par tag, par format/support)
/// - Champs personnalisés Discogs utilisés pour le suivi de cote (prix d'achat, état du média)
enum CollectionPreferencesStore {
    private static func prefix(for username: String) -> String {
        "com.spinlog.pref_\(username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private static func key(_ suffix: String, for username: String) -> String {
        "\(prefix(for: username))_\(suffix)"
    }

    /// Suppression des données du compte : toutes ses préférences (tri, filtres, devise, champs de
    /// suivi de cote, dossiers…), y compris l'ancienne clé du dernier dossier consulté.
    static func clearAccountData(for username: String, defaults: UserDefaults = .standard) {
        let accountPrefix = prefix(for: username) + "_"
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(accountPrefix) {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: "com.spinlog.lastConsultedFolder_\(username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())")
        NotificationCenter.default.post(name: .collectionPreferencesChanged, object: nil)
    }

    // MARK: - Accès génériques UserDefaults (factorisent le get/set/remove/notify répété par
    // chaque préférence ci-dessous ; `notify` ne poste que si un écran a réellement besoin
    // d'être notifié du changement, comme le faisaient les setters d'origine).

    private static func intValue(forKey key: String) -> Int? {
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.integer(forKey: key)
    }

    private static func setValue(_ value: Int?, forKey key: String, notify: Bool = false) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        if notify {
            NotificationCenter.default.post(name: .collectionPreferencesChanged, object: nil)
        }
    }

    private static func setValue(_ value: String?, forKey key: String, removeIfEmpty: Bool = false, notify: Bool = false) {
        if let value, !(removeIfEmpty && value.isEmpty) {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        if notify {
            NotificationCenter.default.post(name: .collectionPreferencesChanged, object: nil)
        }
    }

    // MARK: - Dernier dossier consulté

    static func lastConsultedFolderId(for username: String) -> Int? {
        if let value = intValue(forKey: key("lastFolder", for: username)) {
            return value
        }
        // Clé historique de migration
        let legacyKey = "com.spinlog.lastConsultedFolder_\(username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        return intValue(forKey: legacyKey)
    }

    static func lastConsultedFolderName(for username: String) -> String? {
        UserDefaults.standard.string(forKey: key("lastFolderName", for: username))
    }

    static func setLastConsultedFolderId(_ folderId: Int?, for username: String) {
        setValue(folderId, forKey: key("lastFolder", for: username))
    }

    static func setLastConsultedFolderName(_ name: String?, for username: String) {
        setValue(name, forKey: key("lastFolderName", for: username))
    }

    // MARK: - Dossier d'ajout par défaut

    /// Identifiant spécial correspondant au choix « Toujours demander »
    static let alwaysAskFolderId: Int = -1

    static func defaultAddFolderId(for username: String) -> Int {
        intValue(forKey: key("defaultAddFolderId", for: username)) ?? alwaysAskFolderId
    }

    static func setDefaultAddFolderId(_ folderId: Int, for username: String) {
        setValue(folderId, forKey: key("defaultAddFolderId", for: username), notify: true)
        CloudSyncEngine.shared.markCollectionPreferencesDirty()
    }

    static func isAlwaysAsk(for username: String) -> Bool {
        defaultAddFolderId(for: username) == alwaysAskFolderId
    }

    // MARK: - Critère de tri

    static func sortOption(for username: String) -> CollectionSortOption? {
        guard let raw = UserDefaults.standard.string(forKey: key("sortOption", for: username)) else { return nil }
        return CollectionSortOption(rawValue: raw)
    }

    static func setSortOption(_ option: CollectionSortOption?, for username: String) {
        let changed = option != sortOption(for: username)
        setValue(option?.rawValue, forKey: key("sortOption", for: username))
        if changed { CloudSyncEngine.shared.markCollectionPreferencesDirty() }
    }

    /// `nil` tant que l'utilisateur n'a jamais modifié le sens de tri : l'appelant retombe alors
    /// sur `CollectionSortOption.defaultAscending` pour le critère actif.
    static func sortAscending(for username: String) -> Bool? {
        guard let value = intValue(forKey: key("sortAscending", for: username)) else { return nil }
        return value == 1
    }

    static func setSortAscending(_ ascending: Bool, for username: String) {
        let changed = ascending != sortAscending(for: username)
        setValue(ascending ? 1 : 0, forKey: key("sortAscending", for: username))
        if changed { CloudSyncEngine.shared.markCollectionPreferencesDirty() }
    }

    // MARK: - Tri de la Wantlist

    static func wantlistSortOption(for username: String) -> CollectionSortOption? {
        guard let raw = UserDefaults.standard.string(forKey: key("wantlistSortOption", for: username)) else { return nil }
        return CollectionSortOption(rawValue: raw)
    }

    static func setWantlistSortOption(_ option: CollectionSortOption?, for username: String) {
        let changed = option != wantlistSortOption(for: username)
        setValue(option?.rawValue, forKey: key("wantlistSortOption", for: username))
        if changed { CloudSyncEngine.shared.markCollectionPreferencesDirty() }
    }

    static func wantlistSortAscending(for username: String) -> Bool? {
        guard let value = intValue(forKey: key("wantlistSortAscending", for: username)) else { return nil }
        return value == 1
    }

    static func setWantlistSortAscending(_ ascending: Bool, for username: String) {
        let changed = ascending != wantlistSortAscending(for: username)
        setValue(ascending ? 1 : 0, forKey: key("wantlistSortAscending", for: username))
        if changed { CloudSyncEngine.shared.markCollectionPreferencesDirty() }
    }

    // MARK: - Critères de filtre

    static func filterTags(for username: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key("filterTags", for: username)) ?? []
    }

    static func setFilterTags(_ tags: [String], for username: String) {
        if tags.isEmpty {
            UserDefaults.standard.removeObject(forKey: key("filterTags", for: username))
        } else {
            UserDefaults.standard.set(tags, forKey: key("filterTags", for: username))
        }
    }

    static func filterFormat(for username: String) -> String? {
        UserDefaults.standard.string(forKey: key("filterFormat", for: username))
    }

    static func setFilterFormat(_ format: String?, for username: String) {
        setValue(format, forKey: key("filterFormat", for: username), removeIfEmpty: true)
    }

    static func clearFilterPreferences(for username: String) {
        UserDefaults.standard.removeObject(forKey: key("filterTags", for: username))
        UserDefaults.standard.removeObject(forKey: key("filterFormat", for: username))
    }

    // MARK: - Suivi de cote (prix d'achat)

    /// Identifiant du champ personnalisé Discogs utilisé comme "prix d'achat" (détecté
    /// automatiquement ou choisi manuellement dans les réglages).
    static func purchasePriceFieldId(for username: String) -> Int? {
        intValue(forKey: key("purchasePriceFieldId", for: username))
    }

    static func setPurchasePriceFieldId(_ fieldId: Int?, for username: String) {
        setValue(fieldId, forKey: key("purchasePriceFieldId", for: username), notify: true)
        CloudSyncEngine.shared.markCollectionPreferencesDirty()
    }

    /// Identifiant du champ personnalisé Discogs utilisé comme "état du média" (Media Condition),
    /// pour affiner l'estimation de cote. Détecté automatiquement ou choisi manuellement.
    static func mediaConditionFieldId(for username: String) -> Int? {
        intValue(forKey: key("mediaConditionFieldId", for: username))
    }

    static func setMediaConditionFieldId(_ fieldId: Int?, for username: String) {
        setValue(fieldId, forKey: key("mediaConditionFieldId", for: username), notify: true)
        CloudSyncEngine.shared.markCollectionPreferencesDirty()
    }

    /// Devise principale de la collection, utilisée par défaut à la saisie d'un prix d'achat et
    /// comme cible de conversion pour les comparaisons investi/cote.
    static func defaultCurrency(for username: String) -> String {
        UserDefaults.standard.string(forKey: key("defaultCurrency", for: username)) ?? "EUR"
    }

    static func setDefaultCurrency(_ currency: String, for username: String) {
        setValue(currency, forKey: key("defaultCurrency", for: username), notify: true)
        CloudSyncEngine.shared.markCollectionPreferencesDirty()
    }

    // MARK: - Synchronisation iCloud (compte premium)

    /// Applique un instantané de préférences "durables" reçu d'iCloud (voir `CloudSyncEngine`).
    /// N'écrit qu'en local : ne redéclenche pas d'envoi vers CloudKit, cette donnée en vient déjà.
    static func applyRemotePreferences(
        currency: String,
        purchasePriceFieldId: Int?,
        mediaConditionFieldId: Int?,
        defaultAddFolderId: Int,
        for username: String
    ) {
        // Une seule notification, et seulement si quelque chose a réellement changé : chaque
        // `.collectionPreferencesChanged` fait recharger la page 1 de la collection depuis Discogs
        // (en annulant la synchro de fond en cours). Auparavant, ces quatre écritures en postaient
        // quatre, à chaque réception de cet enregistrement depuis iCloud, même inchangé.
        let changed = currency != defaultCurrency(for: username)
            || purchasePriceFieldId != self.purchasePriceFieldId(for: username)
            || mediaConditionFieldId != self.mediaConditionFieldId(for: username)
            || defaultAddFolderId != self.defaultAddFolderId(for: username)
        guard changed else { return }
        setValue(currency, forKey: key("defaultCurrency", for: username))
        setValue(purchasePriceFieldId, forKey: key("purchasePriceFieldId", for: username))
        setValue(mediaConditionFieldId, forKey: key("mediaConditionFieldId", for: username))
        setValue(defaultAddFolderId, forKey: key("defaultAddFolderId", for: username), notify: true)
    }

    // MARK: - Mode d'affichage et tri, synchronisés (iCloud)

    /// Modes d'affichage (valeurs brutes) tels que connus d'iCloud en dernier : un changement local
    /// n'est signalé que s'il diffère, ce qui évite de renvoyer un mode qu'on vient de recevoir.
    private struct DisplayModes: Equatable {
        var collection: String?
        var wantlist: String?
    }
    private static var lastSyncedDisplayModes = DisplayModes()

    private static var currentDisplayModes: DisplayModes {
        DisplayModes(
            collection: displayModeRawValue(forKey: DisplayPreferenceKeys.collection),
            wantlist: displayModeRawValue(forKey: DisplayPreferenceKeys.wantlist)
        )
    }

    /// Mode d'affichage mémorisé de l'onglet (clé de `DisplayPreferenceKeys`), `nil` s'il n'a jamais été choisi.
    static func displayModeRawValue(forKey key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    /// Appelé quand l'utilisateur change de mode d'affichage (Collection ou Wantlist).
    static func displayModesDidChange() {
        guard currentDisplayModes != lastSyncedDisplayModes else { return }
        lastSyncedDisplayModes = currentDisplayModes
        CloudSyncEngine.shared.markCollectionPreferencesDirty()
    }

    /// Les modes d'affichage actuels viennent d'être envoyés à iCloud (ou reçus de lui).
    static func noteDisplayModesSynced() {
        lastSyncedDisplayModes = currentDisplayModes
    }

    /// Applique le mode d'affichage et le tri reçus d'iCloud. Une valeur absente (appareil sur une version
    /// antérieure) ou inconnue (réglage d'une version plus récente) laisse la valeur locale en place.
    /// N'écrit qu'en local, sans renvoi. Le tri de la Collection passe par `.collectionPreferencesChanged`
    /// (qui relit le tri mémorisé et recharge la page 1), celui de la Wantlist par
    /// `.wantlistPreferencesChanged`, et chaque notification n'est postée que si quelque chose a changé.
    static func applyRemoteViewPreferences(_ prefs: SyncedCollectionPreferences, for username: String) {
        let defaults = UserDefaults.standard
        for (raw, defaultsKey) in [
            (prefs.collectionDisplayMode, DisplayPreferenceKeys.collection),
            (prefs.wantlistDisplayMode, DisplayPreferenceKeys.wantlist)
        ] {
            guard let raw, LibraryDisplayMode(rawValue: raw) != nil, defaults.string(forKey: defaultsKey) != raw else { continue }
            defaults.set(raw, forKey: defaultsKey)
        }
        noteDisplayModesSynced()

        var collectionChanged = false
        if let raw = prefs.collectionSortOption, let option = CollectionSortOption(rawValue: raw), option != sortOption(for: username) {
            setValue(option.rawValue, forKey: key("sortOption", for: username))
            collectionChanged = true
        }
        if let ascending = prefs.collectionSortAscending, ascending != sortAscending(for: username) {
            setValue(ascending ? 1 : 0, forKey: key("sortAscending", for: username))
            collectionChanged = true
        }
        if collectionChanged {
            NotificationCenter.default.post(name: .collectionPreferencesChanged, object: nil)
        }

        var wantlistChanged = false
        if let raw = prefs.wantlistSortOption, let option = CollectionSortOption(rawValue: raw), option != wantlistSortOption(for: username) {
            setValue(option.rawValue, forKey: key("wantlistSortOption", for: username))
            wantlistChanged = true
        }
        if let ascending = prefs.wantlistSortAscending, ascending != wantlistSortAscending(for: username) {
            setValue(ascending ? 1 : 0, forKey: key("wantlistSortAscending", for: username))
            wantlistChanged = true
        }
        if wantlistChanged {
            NotificationCenter.default.post(name: .wantlistPreferencesChanged, object: nil)
        }
    }

    /// Dossier d'ajout par défaut supprimé entre-temps (dans l'app ou sur discogs.com) : retour à
    /// « Toujours demander », sinon chaque ajout visait un dossier inexistant et échouait.
    static func resetDefaultAddFolderIfMissing(validFolderIds: Set<Int>, for username: String) {
        let defaultId = defaultAddFolderId(for: username)
        guard defaultId != alwaysAskFolderId, !validFolderIds.contains(defaultId) else { return }
        setDefaultAddFolderId(alwaysAskFolderId, for: username)
    }

    /// Dossier d'un nouvel ajout sans dossier précisé : le dossier par défaut choisi dans les
    /// réglages, sinon (« Toujours demander ») le dernier dossier consulté, sinon Uncategorized.
    static func folderIdForNewAddition(for username: String) -> Int {
        let defaultId = defaultAddFolderId(for: username)
        if defaultId != alwaysAskFolderId {
            return defaultId
        }
        if let lastFolderId = lastConsultedFolderId(for: username), lastFolderId > 0 {
            return lastFolderId
        }
        return DiscogsConstants.uncategorizedFolderId
    }
}
