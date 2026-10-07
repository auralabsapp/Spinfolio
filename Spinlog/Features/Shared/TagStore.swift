import Foundation
import Observation

/// Tags personnels sur les exemplaires de la collection (niveau `instanceId`).
/// Discogs n'expose aucune API de tags libres (seulement des dossiers de collection, dans lesquels
/// une release ne peut être que dans un seul à la fois) : ces tags sont donc une fonctionnalité propre
/// à l'app, stockée uniquement sur cet appareil et jamais synchronisée avec Discogs.
///
/// La gestion s'effectue par exemplaire (`instanceId`), avec migration transparente et compatibilité
/// pour les anciens tags configurés par `releaseId`.
///
/// Les données sont isolées par compte Discogs (`setActiveUsername`) : se déconnecter puis se
/// reconnecter avec un autre compte donne un espace de tags totalement séparé, et revenir au
/// premier compte restaure les siens.
@Observable
@MainActor
final class TagStore {
    static let shared = TagStore()

    /// Un tag appliqué à un exemplaire, avec sa date d'ajout. Cette date sert à départager quels
    /// tags conserver si une future fusion multi-appareils (iCloud) fait dépasser la limite de
    /// `TagConstants.maxTagsPerInstance` sur un même exemplaire : on garde alors les plus récents.
    private struct TimestampedTag: Codable, Hashable {
        let name: String
        let addedAt: Date
    }

    private var timestampedTagsByInstance: [String: [TimestampedTag]] = [:]
    private(set) var legacyTagsByRelease: [String: [String]] = [:]
    private(set) var standaloneTags: Set<String> = []

    /// Compte Discogs actuellement actif, ou `nil` si personne n'est connecté.
    /// Piloté exclusivement par `DiscogsAuthManager` via `setActiveUsername`.
    private(set) var activeUsername: String?

    /// Tags par exemplaire, exposés sous la forme historique `[instanceId: [nom]]` (sans les dates
    /// d'ajout) pour les consommateurs existants (ex: export de sauvegarde JSON).
    var tagsByInstance: [String: [String]] {
        timestampedTagsByInstance.mapValues { $0.map(\.name) }
    }

    private let instanceStorageKey = "com.spinlog.instanceTags"
    private let legacyReleaseStorageKey = "com.spinlog.releaseTags"
    private let standaloneKey = "com.spinlog.standaloneTags"
    /// Garantit que la migration depuis l'ancien stockage global (avant l'isolation par compte)
    /// ne se produit qu'une seule fois, vers le premier compte activé après cette mise à jour.
    private static let legacyMigrationFlagKey = "com.spinlog.tagStore.migratedToPerAccount"

    private init() {}

    /// Profondeur des `performBatchUpdate` en cours : tant qu'elle est non nulle, `persist()` ne
    /// fait que noter qu'une écriture sera nécessaire à la fin du lot.
    private var batchDepth = 0
    private var needsPersistAfterBatch = false

    /// Regroupe plusieurs modifications en une seule écriture disque et une seule notification
    /// `.tagsChanged`. Sans ça, chaque modification d'un lot (tag ajouté à 500 disques, ou
    /// première synchro iCloud de milliers d'exemplaires) réencodait tout le store et faisait
    /// retrier toute la collection (`CollectionViewModel` observe `.tagsChanged`) à chaque fois.
    func performBatchUpdate(_ updates: () -> Void) {
        batchDepth += 1
        updates()
        batchDepth -= 1
        if batchDepth == 0 && needsPersistAfterBatch {
            needsPersistAfterBatch = false
            persist()
        }
    }

    /// Date d'ajout de chaque tag d'un exemplaire. Tolère les doublons de nom (en gardant la plus
    /// ancienne date) : `Dictionary(uniqueKeysWithValues:)`, utilisé auparavant, fait planter
    /// l'app sur un doublon — possible par exemple après restauration d'une sauvegarde JSON.
    private func addedAtByName(forInstanceKey instanceKey: String) -> [String: Date] {
        Dictionary(
            (timestampedTagsByInstance[instanceKey] ?? []).map { ($0.name, $0.addedAt) },
            uniquingKeysWith: { min($0, $1) }
        )
    }

    /// Bascule ce store sur les données propres au compte Discogs indiqué : sauvegarde déjà à
    /// jour (chaque mutation persiste immédiatement), donc il suffit de recharger l'état en
    /// mémoire depuis le stockage propre à ce compte. Appelé par `DiscogsAuthManager` au
    /// lancement de l'app, à la connexion et à la déconnexion.
    func setActiveUsername(_ username: String?) {
        let normalized = Self.normalize(username)
        guard normalized != activeUsername else { return }
        activeUsername = normalized
        guard let normalized else {
            // Déconnecté : on vide l'état en mémoire sans toucher au disque, pour ne pas laisser
            // les tags d'un compte visibles tant qu'aucun compte n'est actif.
            timestampedTagsByInstance = [:]
            legacyTagsByRelease = [:]
            standaloneTags = []
            return
        }
        load(for: normalized)
    }

    private static func normalize(_ username: String?) -> String? {
        guard let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func key(_ base: String, for username: String) -> String {
        "\(base)_\(username)"
    }

    private func load(for username: String) {
        if let data = UserDefaults.standard.data(forKey: key(instanceStorageKey, for: username)),
           let decoded = try? JSONDecoder().decode([String: [TimestampedTag]].self, from: data) {
            timestampedTagsByInstance = decoded
        } else {
            timestampedTagsByInstance = [:]
        }

        if let data = UserDefaults.standard.data(forKey: key(legacyReleaseStorageKey, for: username)),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            legacyTagsByRelease = decoded
        } else {
            legacyTagsByRelease = [:]
        }

        if let data = UserDefaults.standard.data(forKey: key(standaloneKey, for: username)),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            standaloneTags = decoded
        } else {
            standaloneTags = []
        }

        migrateLegacyDataIfNeeded()
    }

    /// Reprend, une seule fois au total, les données créées avant l'isolation par compte
    /// (stockées sous les clés globales non préfixées) pour le premier compte activé.
    private func migrateLegacyDataIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.legacyMigrationFlagKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.legacyMigrationFlagKey)

        var didMigrate = false

        if timestampedTagsByInstance.isEmpty,
           let data = UserDefaults.standard.data(forKey: instanceStorageKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data),
           !decoded.isEmpty {
            let now = Date()
            timestampedTagsByInstance = decoded.mapValues { names in
                names.map { TimestampedTag(name: $0, addedAt: now) }
            }
            didMigrate = true
        }

        if legacyTagsByRelease.isEmpty,
           let data = UserDefaults.standard.data(forKey: legacyReleaseStorageKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data),
           !decoded.isEmpty {
            legacyTagsByRelease = decoded
            didMigrate = true
        }

        if standaloneTags.isEmpty,
           let data = UserDefaults.standard.data(forKey: standaloneKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data),
           !decoded.isEmpty {
            standaloneTags = decoded
            didMigrate = true
        }

        if didMigrate {
            persist()
        }
    }

    /// Tags associés à un exemplaire physique précis (`instanceId`).
    /// Si aucun tag n'est encore enregistré pour cet exemplaire mais qu'un `releaseId` est fourni,
    /// effectue une migration transparente depuis les anciens tags de la release.
    func tags(for instanceId: Int, releaseId: Int? = nil) -> [String] {
        let instanceKey = String(instanceId)
        if let existing = timestampedTagsByInstance[instanceKey] {
            return existing.map(\.name)
        }
        if let releaseId {
            let releaseKey = String(releaseId)
            if let legacy = legacyTagsByRelease[releaseKey], !legacy.isEmpty {
                return legacy
            }
        } else {
            let legacyKey = String(instanceId)
            if let legacy = legacyTagsByRelease[legacyKey], !legacy.isEmpty {
                return legacy
            }
        }
        return []
    }

    /// Enregistre explicitement une liste de tags (y compris vide) pour un exemplaire précis.
    /// Préserve la date d'ajout des tags déjà présents ; les nouveaux reçoivent la date actuelle.
    func setTags(_ tags: [String], for instanceId: Int) {
        let instanceKey = String(instanceId)
        let existingByName = addedAtByName(forInstanceKey: instanceKey)
        let now = Date()
        // Dédoublonné (insensible à la casse) : un doublon enregistré ici ferait sinon reparaître
        // le même tag deux fois à l'affichage et dans la synchro.
        var seen = Set<String>()
        timestampedTagsByInstance[instanceKey] = tags
            .filter { seen.insert($0.lowercased()).inserted }
            .map { name in TimestampedTag(name: name, addedAt: existingByName[name] ?? now) }
        persist()
        CloudSyncEngine.shared.markTagsDirty(instanceId: instanceId)
    }

    // MARK: - Synchronisation iCloud (compte premium)

    /// Instantané des tags d'un exemplaire sous une forme partageable avec `CloudSyncEngine`
    /// (sans exposer le `TimestampedTag` privé de ce store).
    func syncSnapshot(for instanceId: Int) -> [SyncedTag] {
        (timestampedTagsByInstance[String(instanceId)] ?? []).map { SyncedTag(name: $0.name, addedAt: $0.addedAt) }
    }

    /// Identifiants de tous les exemplaires ayant au moins un tag, pour la synchronisation
    /// initiale : les tags créés avant l'existence de `CloudSyncEngine` (ou avant l'activation du
    /// compte premium) n'ont jamais déclenché `markTagsDirty` — il faut donc les repousser
    /// explicitement à chaque activation de compte, pas seulement les futures modifications.
    func allTaggedInstanceIds() -> [Int] {
        timestampedTagsByInstance.keys.compactMap { Int($0) }
    }

    /// Applique un état de tags déjà fusionné (voir `TagMergeLogic`) reçu depuis iCloud pour un
    /// exemplaire donné. N'écrit qu'en local : ne redéclenche pas d'envoi vers CloudKit, cette
    /// donnée en vient déjà.
    func applyRemoteTags(instanceId: Int, tags: [SyncedTag]) {
        let instanceKey = String(instanceId)
        if tags.isEmpty {
            timestampedTagsByInstance.removeValue(forKey: instanceKey)
        } else {
            timestampedTagsByInstance[instanceKey] = tags.map { TimestampedTag(name: $0.name, addedAt: $0.addedAt) }
        }
        persist()
    }

    /// Applique un état de tags autonomes déjà fusionné (voir `CloudSyncEngine`) reçu depuis
    /// iCloud. N'écrit qu'en local : ne redéclenche pas d'envoi vers CloudKit, cette donnée en
    /// vient déjà.
    func applyRemoteStandaloneTags(_ tags: Set<String>) {
        standaloneTags = tags
        persist()
    }

    /// Réassigne les tags d'un identifiant d'exemplaire temporaire vers l'identifiant définitif Discogs.
    func remapInstanceId(from oldInstanceId: Int, to newInstanceId: Int) {
        let oldKey = String(oldInstanceId)
        let newKey = String(newInstanceId)
        if let entries = timestampedTagsByInstance[oldKey] {
            timestampedTagsByInstance[newKey] = entries
            timestampedTagsByInstance.removeValue(forKey: oldKey)
            persist()
            CloudSyncEngine.shared.markTagsDirty(instanceId: newInstanceId)
        }
    }

    /// Nombre d'exemplaires physiques sur lesquels ce tag est appliqué.
    func instanceCount(for tag: String) -> Int {
        let fromInstances = timestampedTagsByInstance.values.filter { entries in
            entries.contains { $0.name == tag }
        }.count
        if fromInstances > 0 {
            return fromInstances
        }
        return legacyTagsByRelease.values.filter { $0.contains(tag) }.count
    }

    /// Alias pour rétrocompatibilité
    func releaseCount(for tag: String) -> Int {
        instanceCount(for: tag)
    }

    /// Tous les tags créés (associés à des exemplaires ou créés de façon autonome), triés alphabétiquement.
    var allTags: [String] {
        let fromInstances = timestampedTagsByInstance.values.flatMap { $0.map(\.name) }
        let fromReleases = legacyTagsByRelease.values.flatMap { $0 }
        return Set(fromInstances).union(fromReleases).union(standaloneTags)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Renvoie le nom exact d'un tag existant correspondant (insensible à la casse).
    func existingTag(matching name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return allTags.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    /// Crée un nouveau tag dans la bibliothèque sans nécessairement l'associer immédiatement à un disque.
    func createTag(_ tag: String) {
        let trimmed = String(tag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(TagConstants.maxNameLength))
        guard !trimmed.isEmpty else { return }
        guard !allTags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        standaloneTags.insert(trimmed)
        persist()
        CloudSyncEngine.shared.markStandaloneTagsDirty()
    }

    /// Ajoute un tag à un exemplaire spécifique (`instanceId`).
    func addTag(_ tag: String, to instanceId: Int, releaseId: Int? = nil) {
        let trimmed = String(tag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(TagConstants.maxNameLength))
        guard !trimmed.isEmpty else { return }
        let instanceKey = String(instanceId)
        let currentNames = tags(for: instanceId, releaseId: releaseId)
        guard !currentNames.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }

        let existingByName = addedAtByName(forInstanceKey: instanceKey)
        let now = Date()
        var updated = currentNames.map { name in TimestampedTag(name: name, addedAt: existingByName[name] ?? now) }
        updated.append(TimestampedTag(name: trimmed, addedAt: now))
        timestampedTagsByInstance[instanceKey] = updated
        persist()
        CloudSyncEngine.shared.markTagsDirty(instanceId: instanceId)
    }

    /// Retire un tag d'un exemplaire spécifique (`instanceId`).
    func removeTag(_ tag: String, from instanceId: Int, releaseId: Int? = nil) {
        let instanceKey = String(instanceId)
        var currentNames = tags(for: instanceId, releaseId: releaseId)
        // Tag absent : rien à faire. Évite, lors d'un retrait en lot, de réécrire et de renvoyer
        // vers iCloud les exemplaires qui ne portaient pas ce tag.
        guard currentNames.contains(tag) else { return }
        currentNames.removeAll { $0 == tag }
        if currentNames.isEmpty {
            timestampedTagsByInstance.removeValue(forKey: instanceKey)
        } else {
            let existingByName = addedAtByName(forInstanceKey: instanceKey)
            let now = Date()
            timestampedTagsByInstance[instanceKey] = currentNames.map { name in
                TimestampedTag(name: name, addedAt: existingByName[name] ?? now)
            }
        }
        persist()
        CloudSyncEngine.shared.markTagsDirty(instanceId: instanceId)
    }

    /// Supprime tous les tags associés à un exemplaire supprimé.
    func removeTags(for instanceId: Int) {
        let instanceKey = String(instanceId)
        if timestampedTagsByInstance.removeValue(forKey: instanceKey) != nil {
            persist()
            CloudSyncEngine.shared.markTagsDirty(instanceId: instanceId)
        }
    }

    /// Renomme un tag partout où il est utilisé et dans les tags autonomes.
    func renameTag(_ oldTag: String, to newName: String) {
        let trimmed = String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(TagConstants.maxNameLength))
        guard !trimmed.isEmpty, trimmed != oldTag else { return }

        if standaloneTags.contains(oldTag) {
            standaloneTags.remove(oldTag)
            standaloneTags.insert(trimmed)
        }

        var dirtyInstanceIds: [Int] = []
        for (key, entries) in timestampedTagsByInstance {
            if entries.contains(where: { $0.name == oldTag }) {
                var updated = entries.map { entry in
                    entry.name == oldTag ? TimestampedTag(name: trimmed, addedAt: entry.addedAt) : entry
                }
                var seen = Set<String>()
                updated = updated.filter { seen.insert($0.name.lowercased()).inserted }
                timestampedTagsByInstance[key] = updated
                if let instanceId = Int(key) { dirtyInstanceIds.append(instanceId) }
            }
        }

        for (key, tags) in legacyTagsByRelease {
            if tags.contains(oldTag) {
                var updated = tags.map { $0 == oldTag ? trimmed : $0 }
                var seen = Set<String>()
                updated = updated.filter { seen.insert($0.lowercased()).inserted }
                legacyTagsByRelease[key] = updated
            }
        }

        persist()
        CloudSyncEngine.shared.markStandaloneTagsDirty()
        for instanceId in dirtyInstanceIds { CloudSyncEngine.shared.markTagsDirty(instanceId: instanceId) }
    }

    /// Supprime définitivement un tag : retiré de tous les exemplaires et de la liste globale.
    func deleteTag(_ tag: String) {
        standaloneTags.remove(tag)

        var dirtyInstanceIds: [Int] = []
        for (key, entries) in timestampedTagsByInstance {
            let updated = entries.filter { $0.name != tag }
            if updated.isEmpty {
                timestampedTagsByInstance.removeValue(forKey: key)
                if let instanceId = Int(key) { dirtyInstanceIds.append(instanceId) }
            } else if updated.count != entries.count {
                timestampedTagsByInstance[key] = updated
                if let instanceId = Int(key) { dirtyInstanceIds.append(instanceId) }
            }
        }

        for (key, tags) in legacyTagsByRelease {
            var updated = tags
            updated.removeAll { $0 == tag }
            if updated.isEmpty {
                legacyTagsByRelease.removeValue(forKey: key)
            } else {
                legacyTagsByRelease[key] = updated
            }
        }

        persist()
        CloudSyncEngine.shared.markStandaloneTagsDirty()
        for instanceId in dirtyInstanceIds { CloudSyncEngine.shared.markTagsDirty(instanceId: instanceId) }
    }

    /// Restauration des données de tags à partir d'une sauvegarde. Les tags importés reçoivent
    /// la date de restauration comme date d'ajout (une sauvegarde JSON ne porte pas cette info).
    func restoreData(
        tagsByInstance: [String: [String]]?,
        tagsByRelease: [String: [String]],
        standaloneTags: Set<String>
    ) {
        let previousInstanceIds = Set(allTaggedInstanceIds())
        if let tagsByInstance {
            let now = Date()
            self.timestampedTagsByInstance = tagsByInstance.mapValues { names in
                // Dédoublonné : une sauvegarde éditée à la main peut contenir un doublon.
                var seen = Set<String>()
                return names
                    .filter { seen.insert($0.lowercased()).inserted }
                    .map { TimestampedTag(name: $0, addedAt: now) }
            }
        }
        self.legacyTagsByRelease = tagsByRelease
        self.standaloneTags = standaloneTags
        persist()

        // Sans ces signalements, la restauration restait purement locale : iCloud gardait l'état
        // d'avant (y compris des tags que la sauvegarde ne contient plus) et pouvait le réappliquer
        // au prochain fetch. On renvoie donc tous les exemplaires concernés, avant et après.
        for instanceId in previousInstanceIds.union(allTaggedInstanceIds()) {
            CloudSyncEngine.shared.markTagsDirty(instanceId: instanceId)
        }
        CloudSyncEngine.shared.markStandaloneTagsDirty()
    }

    private func persist() {
        guard batchDepth == 0 else {
            needsPersistAfterBatch = true
            return
        }
        guard let activeUsername else { return }
        if let data = try? JSONEncoder().encode(timestampedTagsByInstance) {
            UserDefaults.standard.set(data, forKey: key(instanceStorageKey, for: activeUsername))
        }
        if let data = try? JSONEncoder().encode(legacyTagsByRelease) {
            UserDefaults.standard.set(data, forKey: key(legacyReleaseStorageKey, for: activeUsername))
        }
        if let data = try? JSONEncoder().encode(standaloneTags) {
            UserDefaults.standard.set(data, forKey: key(standaloneKey, for: activeUsername))
        }
        NotificationCenter.default.post(name: .tagsChanged, object: nil)
    }
}


extension Notification.Name {
    static let tagsChanged = Notification.Name("com.spinlog.tagsChanged")
}
