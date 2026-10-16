import Foundation
import SwiftData
import WidgetKit
import OSLog

private let widgetSnapshotLogger = Logger(subsystem: "com.aurelienscarpa.Spinlog", category: "WidgetSnapshotSync")
private let localDataStoreLogger = Logger(subsystem: "com.aurelienscarpa.Spinlog", category: "LocalDataStore")

@Model
final class CachedCollectionEntry {
    @Attribute(.unique) var id: String
    var username: String
    var folderId: Int
    var releaseId: Int
    var instanceId: Int
    var payload: Data
    var lastFetchedAt: Date

    init(username: String, folderId: Int, releaseId: Int, instanceId: Int, payload: Data, lastFetchedAt: Date = Date()) {
        self.id = "\(username)_\(folderId)_\(instanceId)"
        self.username = username
        self.folderId = folderId
        self.releaseId = releaseId
        self.instanceId = instanceId
        self.payload = payload
        self.lastFetchedAt = lastFetchedAt
    }
}

@Model
final class CachedWantlistEntry {
    @Attribute(.unique) var id: String
    var username: String
    var releaseId: Int
    var payload: Data
    var lastFetchedAt: Date

    init(username: String, releaseId: Int, payload: Data, lastFetchedAt: Date = Date()) {
        self.id = "\(username)_\(releaseId)"
        self.username = username
        self.releaseId = releaseId
        self.payload = payload
        self.lastFetchedAt = lastFetchedAt
    }
}

@Model
final class CachedFolderEntry {
    @Attribute(.unique) var id: String
    var username: String
    var folderId: Int
    var payload: Data
    var lastFetchedAt: Date

    init(username: String, folderId: Int, payload: Data, lastFetchedAt: Date = Date()) {
        self.id = "\(username)_\(folderId)"
        self.username = username
        self.folderId = folderId
        self.payload = payload
        self.lastFetchedAt = lastFetchedAt
    }
}

@Model
final class CachedFetchMetadata {
    @Attribute(.unique) var id: String
    var lastFetchedAt: Date

    init(id: String, lastFetchedAt: Date = Date()) {
        self.id = id
        self.lastFetchedAt = lastFetchedAt
    }
}

/// Gestionnaire de persistance locale basé sur SwiftData avec règle de TTL de 6 heures.
@MainActor
final class LocalDataStore {
    static let shared = LocalDataStore()

    private let container: ModelContainer
    private let context: ModelContext

    private init() {
        let schema = Schema([
            CachedCollectionEntry.self,
            CachedWantlistEntry.self,
            CachedFolderEntry.self,
            CachedFetchMetadata.self,
            MasterRecord.self,
            CollectionSnapshot.self,
            ReleasePriceSnapshot.self
        ])
        // `cloudKitDatabase: .none` est explicite : ce cache Discogs est jetable et retéléchargeable
        // (TTL 6h), il ne doit jamais être mirroré vers CloudKit. Sans ce paramètre, SwiftData
        // active automatiquement la synchronisation CloudKit dès que l'app a la capacité iCloud —
        // et ce schéma (contraintes uniques, attributs non optionnels) n'y est pas compatible,
        // ce qui fait planter le chargement du container au lancement.
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
            context = ModelContext(container)
        } catch {
            // Fallback en mémoire en cas d'erreur de schéma : rien ne sera conservé entre deux
            // lancements, d'où ce log (auparavant silencieux) pour pouvoir diagnostiquer.
            localDataStoreLogger.fault("Échec d'ouverture du store SwiftData, repli en mémoire : \(error, privacy: .public)")
            let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            container = (try? ModelContainer(for: schema, configurations: [inMemoryConfig]))
                ?? (try! ModelContainer(for: Schema([]), configurations: []))
            context = ModelContext(container)
        }
    }

    // MARK: - Master Records (Années originales immuables)

    /// Copie mémoire COMPLÈTE de la table des MasterRecords, chargée une fois puis tenue à jour
    /// par `saveMasterYear`/`saveMasterYears`. Auparavant, `getMasterYear`/`saveMasterYear`
    /// pouvaient la créer partielle avant le premier `getAllMasterYears`, qui la renvoyait ensuite
    /// telle quelle : des masters déjà connus semblaient manquants et étaient redemandés à Discogs.
    private var masterYearsMemoryCache: [Int: Int]?

    private func loadedMasterYears() -> [Int: Int] {
        if let cache = masterYearsMemoryCache {
            return cache
        }
        let descriptor = FetchDescriptor<MasterRecord>()
        let records = (try? context.fetch(descriptor)) ?? []
        var result: [Int: Int] = [:]
        result.reserveCapacity(records.count)
        for record in records {
            result[record.masterId] = record.originalYear
        }
        masterYearsMemoryCache = result
        return result
    }

    /// Récupère tous les MasterRecords déjà connus sous forme de dictionnaire [masterId: originalYear].
    func getAllMasterYears() -> [Int: Int] {
        loadedMasterYears()
    }

    /// Récupère l'année originale d'un master particulier si présente en cache. Simple lecture
    /// du dictionnaire en mémoire : auparavant, chaque master inconnu déclenchait sa propre
    /// requête SwiftData, pour toute la collection, à chaque page chargée en tri "rangement".
    func getMasterYear(for masterId: Int) -> Int? {
        guard let year = loadedMasterYears()[masterId] else { return nil }
        return year > 0 ? year : nil
    }

    /// Indique si ce master a déjà été résolu (même sans année connue, enregistrée à 0).
    func isMasterResolved(_ masterId: Int) -> Bool {
        loadedMasterYears()[masterId] != nil
    }

    /// Enregistre ou met à jour l'année originale d'un Master.
    func saveMasterYear(_ year: Int, for masterId: Int) {
        _ = loadedMasterYears()
        masterYearsMemoryCache?[masterId] = year

        let descriptor = FetchDescriptor<MasterRecord>(
            predicate: #Predicate<MasterRecord> { $0.masterId == masterId }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.originalYear = year
            existing.fetchedAt = Date()
        } else {
            let record = MasterRecord(masterId: masterId, originalYear: year)
            context.insert(record)
        }
        try? context.save()

        NotificationCenter.default.post(
            name: .masterYearResolved,
            object: nil,
            userInfo: ["masterId": masterId, "year": year]
        )
    }

    /// Restaure en masse une table masterId -> année depuis une sauvegarde, sans écraser une
    /// donnée déjà connue localement plus récemment que la restauration (les deux sont la même
    /// valeur immuable en pratique, mais on n'écrase jamais un enregistrement existant pour éviter
    /// de perdre un `fetchedAt` plus précis).
    func saveMasterYears(_ years: [Int: Int]) {
        guard !years.isEmpty else { return }
        let existing = getAllMasterYears()
        for (masterId, year) in years where existing[masterId] == nil {
            context.insert(MasterRecord(masterId: masterId, originalYear: year))
            masterYearsMemoryCache?[masterId] = year
        }
        try? context.save()
    }

    // MARK: - Value Snapshots (Cote & Prix d'achat)

    /// Enregistre un nouveau point d'historique de la valeur globale de la collection, ou met à
    /// jour celui du jour s'il existe déjà (au plus un point par jour).
    func saveCollectionSnapshot(currency: String, low: Double, median: Double, high: Double) {
        let snapshot = CollectionSnapshot(currency: currency, low: low, median: median, high: high)
        let targetId = snapshot.id
        let descriptor = FetchDescriptor<CollectionSnapshot>(
            predicate: #Predicate<CollectionSnapshot> { $0.id == targetId }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.date = snapshot.date
            existing.currency = currency
            existing.low = low
            existing.median = median
            existing.high = high
        } else {
            context.insert(snapshot)
        }
        try? context.save()
        CloudSyncEngine.shared.markCollectionSnapshotDirty(dayStamp: targetId)
    }

    /// Point d'historique de collection le plus récent (pour déterminer si un rafraîchissement
    /// est nécessaire, ou pour afficher la dernière valeur connue).
    func latestCollectionSnapshot() -> CollectionSnapshot? {
        var descriptor = FetchDescriptor<CollectionSnapshot>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Historique complet, trié chronologiquement, pour le graphique d'évolution de la valeur.
    func allCollectionSnapshots() -> [CollectionSnapshot] {
        let descriptor = FetchDescriptor<CollectionSnapshot>(sortBy: [SortDescriptor(\.date, order: .forward)])
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Synchronisation iCloud (compte premium)

    /// Identifiants (jour, "yyyy-MM-dd") de tous les points d'historique de collection, pour la
    /// synchronisation initiale (même besoin que `TagStore.allTaggedInstanceIds()`).
    func collectionSnapshotDayStamps() -> [String] {
        allCollectionSnapshots().map(\.id)
    }

    /// Point d'historique correspondant à ce jour, pour construire le contenu à envoyer vers
    /// iCloud.
    func collectionSnapshot(dayStamp: String) -> CollectionSnapshot? {
        let descriptor = FetchDescriptor<CollectionSnapshot>(
            predicate: #Predicate<CollectionSnapshot> { $0.id == dayStamp }
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// Applique un point d'historique reçu d'iCloud (ajout ou mise à jour). N'écrit qu'en local :
    /// ne redéclenche pas d'envoi vers CloudKit, cette donnée en vient déjà.
    func applyRemoteCollectionSnapshot(
        dayStamp: String,
        date: Date,
        currency: String,
        low: Double,
        median: Double,
        high: Double
    ) {
        let descriptor = FetchDescriptor<CollectionSnapshot>(
            predicate: #Predicate<CollectionSnapshot> { $0.id == dayStamp }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.date = date
            existing.currency = currency
            existing.low = low
            existing.median = median
            existing.high = high
        } else {
            context.insert(CollectionSnapshot(date: date, currency: currency, low: low, median: median, high: high))
        }
        try? context.save()
        NotificationCenter.default.post(name: .collectionSnapshotsChanged, object: nil)
    }

    /// Enregistre un nouveau point d'historique de prix pour une release, ou met à jour celui du
    /// jour s'il existe déjà (au plus un point par jour et par release).
    func saveReleasePriceSnapshot(releaseId: Int, currency: String, medianPrice: Double, condition: String?) {
        let snapshot = ReleasePriceSnapshot(releaseId: releaseId, currency: currency, medianPrice: medianPrice, condition: condition)
        let targetId = snapshot.id
        let descriptor = FetchDescriptor<ReleasePriceSnapshot>(
            predicate: #Predicate<ReleasePriceSnapshot> { $0.id == targetId }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.date = snapshot.date
            existing.currency = currency
            existing.medianPrice = medianPrice
            existing.condition = condition
        } else {
            context.insert(snapshot)
        }
        try? context.save()
    }

    /// Dernier point de prix connu pour une release (pour déterminer si un rafraîchissement est
    /// nécessaire, et afficher une estimation immédiate sans attendre le réseau).
    func latestReleasePriceSnapshot(releaseId: Int) -> ReleasePriceSnapshot? {
        var descriptor = FetchDescriptor<ReleasePriceSnapshot>(
            predicate: #Predicate<ReleasePriceSnapshot> { $0.releaseId == releaseId },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Collection

    /// Nombre d'éléments par lot dans les grosses boucles d'écriture ci-dessous. Réduit de 25 à 10
    /// (mesuré à l'Instruments : tranches de ~94ms pendant la synchro de fond au lancement de
    /// l'app, période où elle traite plusieurs pages de 100 éléments coup sur coup pendant que
    /// l'utilisateur consulte déjà la Collection) — des lots plus petits cèdent la main plus
    /// souvent, donc des à-coups plus courts, au prix de `context.save()` un peu plus fréquents
    /// (incrémental, donc bon marché par rapport à l'encodage JSON de chaque lot).
    private static let writeBatchSize = 10

    /// Point de reprise coopératif entre deux lots d'écriture : sauvegarde le lot courant puis
    /// rend la main au run loop. `LocalDataStore` reste sur l'acteur principal (SwiftData et les
    /// 20+ sites d'appel synchrones de ce store l'exigent) — ce point de reprise ne déplace donc
    /// pas le travail hors du thread principal, il le fragmente en tranches au lieu d'un seul bloc
    /// ininterrompu. Sans lui, `syncCollectionFolder` en fin de synchro de fond ré-encodait toute la
    /// collection (JSON + SwiftData) d'un coup, provoquant les gels de plusieurs secondes mesurés
    /// dans Instruments juste après le lancement/connexion.
    private func saveAndYieldIfNeeded(_ index: Int) async {
        guard index > 0, index % Self.writeBatchSize == 0 else { return }
        try? context.save()
        await Task.yield()
    }

    func saveCollectionItems(_ items: [CollectionItem], username: String, folderId: Int) async {
        let now = Date()
        let encoder = JSONEncoder()

        for (index, item) in items.enumerated() {
            guard let data = try? encoder.encode(item) else { continue }
            let entry = CachedCollectionEntry(
                username: username,
                folderId: folderId,
                releaseId: item.releaseId,
                instanceId: item.instanceId,
                payload: data,
                lastFetchedAt: now
            )
            context.insert(entry)
            await saveAndYieldIfNeeded(index)
        }

        // Met à jour l'horodatage global pour ce dossier
        let metaId = "\(username)_collection_\(folderId)"
        let meta = CachedFetchMetadata(id: metaId, lastFetchedAt: now)
        context.insert(meta)

        try? context.save()

        // Appelé à chaque page pendant la synchro de fond : on se contente ici d'amorcer un
        // widget encore vide. Relire et décoder toute la collection à chaque page (comme avant)
        // rendait la synchro quadratique sur le main actor ; l'instantané complet est écrit une
        // seule fois, en fin de synchro, par `syncCollectionFolder`.
        if WidgetSnapshotStore.loadCollection().isEmpty {
            let all = getAllCollectionItemsSync(username: username)
            if !all.isEmpty {
                updateWidgetSnapshot(all)
            }
        }
    }

    /// Vrai s'il existe au moins un autre exemplaire de cette release que celui exclu. Aucun
    /// décodage JSON ici (contrairement à l'ancien appel qui décodait toute la collection "All"
    /// rien que pour comparer des `instanceId`) : `instanceId` est un champ propre du modèle
    /// SwiftData, directement filtrable par la requête.
    func hasOtherCollectionInstance(username: String, releaseId: Int, excludingInstanceId: Int?) -> Bool {
        var descriptor = FetchDescriptor<CachedCollectionEntry>(
            predicate: #Predicate<CachedCollectionEntry> {
                $0.username == username && $0.releaseId == releaseId
            }
        )
        descriptor.propertiesToFetch = [\.instanceId]
        guard let entries = try? context.fetch(descriptor) else { return false }
        if let excludingInstanceId {
            return entries.contains { $0.instanceId != excludingInstanceId }
        }
        return !entries.isEmpty
    }

    /// Nombre de disques distincts (par release, comme l'instantané du widget) en cache pour ce
    /// compte, sans décoder les payloads JSON.
    private func cachedReleaseCount(username: String) -> Int {
        var descriptor = FetchDescriptor<CachedCollectionEntry>(
            predicate: #Predicate<CachedCollectionEntry> { $0.username == username }
        )
        descriptor.propertiesToFetch = [\.releaseId]
        guard let entries = try? context.fetch(descriptor) else { return 0 }
        return Set(entries.map(\.releaseId)).count
    }

    func syncCollectionFolder(username: String, folderId: Int, fullItems: [CollectionItem]) async {
        let now = Date()
        let encoder = JSONEncoder()

        let deleteDescriptor = FetchDescriptor<CachedCollectionEntry>(
            predicate: #Predicate<CachedCollectionEntry> {
                $0.username == username && $0.folderId == folderId
            }
        )
        if let oldEntries = try? context.fetch(deleteDescriptor) {
            for (index, entry) in oldEntries.enumerated() {
                context.delete(entry)
                await saveAndYieldIfNeeded(index)
            }
        }

        for (index, item) in fullItems.enumerated() {
            guard item.instanceId > 0 && item.instanceId != item.releaseId else { continue }
            guard let data = try? encoder.encode(item) else { continue }
            let entry = CachedCollectionEntry(
                username: username,
                folderId: folderId,
                releaseId: item.releaseId,
                instanceId: item.instanceId,
                payload: data,
                lastFetchedAt: now
            )
            context.insert(entry)
            await saveAndYieldIfNeeded(index)
        }

        let metaId = "\(username)_collection_\(folderId)"
        let meta = CachedFetchMetadata(id: metaId, lastFetchedAt: now)
        context.insert(meta)

        try? context.save()

        // Le dossier "All" (agrégat complet) est le reflet fidèle de toute la collection.
        // Si folderId est "All", on met à jour le widget avec ces items.
        // Si folderId n'est pas "All" mais que le widget est vide ou incomplet, on l'alimente avec le maximum de disques disponibles.
        if folderId == DiscogsConstants.allFolderId {
            updateWidgetSnapshot(fullItems)
        } else {
            // Comparaison en disques distincts (l'instantané du widget est dédoublonné par
            // release) : comparer des exemplaires à des disques, comme avant, était toujours vrai
            // dès qu'un disque était possédé en plusieurs exemplaires, et réécrivait le widget à
            // chaque appel. Le décodage complet n'a lieu que si une mise à jour est nécessaire.
            let knownReleaseCount = cachedReleaseCount(username: username)
            let currentSnapshotCount = WidgetSnapshotStore.loadCollection().count
            if knownReleaseCount > 0 && (currentSnapshotCount == 0 || knownReleaseCount > currentSnapshotCount) {
                updateWidgetSnapshot(getAllCollectionItemsSync(username: username))
            }
        }
    }

    /// Ravitaille le widget "Album du jour" à partir de tous les disques de la collection en cache.
    func refreshWidgetSnapshot(username: String) {
        let all = getAllCollectionItemsSync(username: username)
        guard !all.isEmpty else { return }
        updateWidgetSnapshot(all)
    }

    /// Réduit la collection à un instantané léger (id, titre, artiste, pochette) pour le widget
    /// "Album du jour", dédoublonné par release (plusieurs exemplaires d'un même disque ne
    /// doivent compter qu'une fois dans le tirage aléatoire).
    func updateWidgetSnapshot(_ items: [CollectionItem]) {
        var seenReleaseIds = Set<Int>()
        var snapshot: [RandomAlbumSnapshotItem] = []
        for item in items {
            guard item.releaseId > 0,
                  seenReleaseIds.insert(item.releaseId).inserted else { continue }
            snapshot.append(RandomAlbumSnapshotItem(
                releaseId: item.releaseId,
                title: item.basicInformation.title,
                artistNames: item.basicInformation.artistNames,
                coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb
            ))
        }
        widgetSnapshotLogger.log("updateWidgetSnapshot : \(items.count) exemplaire(s) en entrée -> \(snapshot.count) disque(s) uniques écrits dans l'App Group.")
        WidgetSnapshotStore.saveCollection(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.randomAlbum)
    }

    /// Décodage pur, sans affinité d'acteur : exécuté depuis une `Task.detached` par les méthodes
    /// `async` ci-dessous, pour que le JSON d'une grosse collection (potentiellement des centaines
    /// d'exemplaires) se décode hors du fil principal plutôt que de bloquer l'UI pendant cette
    /// passe CPU. `CollectionItem` est `Sendable`, donc son résultat traverse la frontière d'acteur
    /// sans copie défensive supplémentaire.
    nonisolated private static func decodeCollectionItems(from payloads: [Data]) -> [CollectionItem] {
        let decoder = JSONDecoder()
        return payloads.compactMap { try? decoder.decode(CollectionItem.self, from: $0) }
    }

    func getCollectionItems(username: String, folderId: Int) async -> [CollectionItem] {
        let descriptor = FetchDescriptor<CachedCollectionEntry>(
            predicate: #Predicate<CachedCollectionEntry> {
                $0.username == username && $0.folderId == folderId
            }
        )
        guard let entries = try? context.fetch(descriptor) else { return [] }
        let payloads = entries.map(\.payload)
        return await Task.detached(priority: .userInitiated) {
            Self.decodeCollectionItems(from: payloads)
        }.value
    }

    func getAllCollectionItems(username: String) async -> [CollectionItem] {
        let allInFolder0 = await getCollectionItems(username: username, folderId: DiscogsConstants.allFolderId)
        let descriptor = FetchDescriptor<CachedCollectionEntry>(
            predicate: #Predicate<CachedCollectionEntry> {
                $0.username == username
            }
        )
        guard let entries = try? context.fetch(descriptor) else { return allInFolder0 }
        let payloads = entries.map(\.payload)
        let decoded = await Task.detached(priority: .userInitiated) {
            Self.decodeCollectionItems(from: payloads)
        }.value
        var seen = Set<Int>()
        var items: [CollectionItem] = []
        for item in decoded where !seen.contains(item.instanceId) {
            seen.insert(item.instanceId)
            items.append(item)
        }
        return items.count > allInFolder0.count ? items : allInFolder0
    }

    /// Variante synchrone de `getAllCollectionItems`, pour les quelques appelants hors contexte
    /// `async` (bookkeeping interne du widget ; écrans secondaires comme la personnalisation du
    /// tri des artistes ou le placement en rayon, dont les propriétés calculées de vue ne peuvent
    /// pas devenir `async` sans une restructuration que leur fréquence d'usage ne justifie pas).
    /// Hors du chemin de chargement affiché à l'utilisateur au lancement (Collection/Stats), seul
    /// vrai objectif de la variante `async`.
    func getAllCollectionItemsSync(username: String) -> [CollectionItem] {
        let descriptor = FetchDescriptor<CachedCollectionEntry>(
            predicate: #Predicate<CachedCollectionEntry> {
                $0.username == username
            }
        )
        guard let entries = try? context.fetch(descriptor) else { return [] }
        let decoded = Self.decodeCollectionItems(from: entries.map(\.payload))
        var seen = Set<Int>()
        var items: [CollectionItem] = []
        for item in decoded where !seen.contains(item.instanceId) {
            seen.insert(item.instanceId)
            items.append(item)
        }
        return items
    }

    /// Récupère l'ensemble des exemplaires d'une release donnée enregistrés pour un utilisateur.
    /// Synchrone (contrairement à `getAllCollectionItems`) : filtré par release, son volume reste
    /// toujours minime (quelques exemplaires d'un même disque au plus) — passer par
    /// `Task.detached` ici coûterait plus cher que le décodage lui-même, et casserait la garantie
    /// "latence nulle" documentée par certains appelants (ex. `ReleaseActions.prepareInitialStatus`).
    func getCollectionItems(username: String, releaseId: Int) -> [CollectionItem] {
        let descriptor = FetchDescriptor<CachedCollectionEntry>(
            predicate: #Predicate<CachedCollectionEntry> {
                $0.username == username && $0.releaseId == releaseId
            }
        )
        guard let entries = try? context.fetch(descriptor) else { return [] }
        let decoded = Self.decodeCollectionItems(from: entries.map(\.payload))
        var seen = Set<Int>()
        var items: [CollectionItem] = []
        for item in decoded {
            if !seen.contains(item.instanceId) {
                seen.insert(item.instanceId)
                items.append(item)
            }
        }
        return items
    }

    func removeCollectionItem(username: String, folderId: Int, instanceId: Int) {
        let targetId = "\(username)_\(folderId)_\(instanceId)"
        let descriptor = FetchDescriptor<CachedCollectionEntry>(
            predicate: #Predicate<CachedCollectionEntry> { $0.id == targetId }
        )
        if let entries = try? context.fetch(descriptor) {
            for entry in entries {
                context.delete(entry)
            }
            try? context.save()
            refreshWidgetSnapshot(username: username)
        }
    }

    func removeCollectionItems(username: String, releaseId: Int) {
        let descriptor = FetchDescriptor<CachedCollectionEntry>(
            predicate: #Predicate<CachedCollectionEntry> {
                $0.username == username && $0.releaseId == releaseId
            }
        )
        if let entries = try? context.fetch(descriptor) {
            for entry in entries {
                context.delete(entry)
            }
            try? context.save()
            refreshWidgetSnapshot(username: username)
        }
    }

    /// Nettoie les entrées corrompues ou fantômes (instanceId invalide ou égal au releaseId).
    func cleanupPhantomCollectionEntries(username: String) {
        let descriptor = FetchDescriptor<CachedCollectionEntry>(
            predicate: #Predicate<CachedCollectionEntry> {
                $0.username == username
            }
        )
        if let entries = try? context.fetch(descriptor) {
            var hasChanges = false
            for entry in entries {
                if entry.instanceId <= 0 || entry.instanceId == entry.releaseId {
                    context.delete(entry)
                    hasChanges = true
                }
            }
            if hasChanges {
                try? context.save()
            }
        }
    }

    func lastCollectionFetchedAt(username: String, folderId: Int) -> Date? {
        let targetId = "\(username)_collection_\(folderId)"
        let descriptor = FetchDescriptor<CachedFetchMetadata>(
            predicate: #Predicate<CachedFetchMetadata> { $0.id == targetId }
        )
        return (try? context.fetch(descriptor))?.first?.lastFetchedAt
    }

    func isCollectionStale(username: String, folderId: Int) -> Bool {
        guard let date = lastCollectionFetchedAt(username: username, folderId: folderId) else {
            return true
        }
        return Date().timeIntervalSince(date) >= DiscogsConstants.sixHoursTTL
    }

    // MARK: - Outils Développeur / Simulation

    /// Simule un cache plus vieux que 6 heures (7h en arrière) pour tester l'apparition
    /// des bandeaux hors ligne et le comportement de synchronisation selon la règle Discogs.
    func simulateStaleCache(username: String) {
        let sevenHoursAgo = Date().addingTimeInterval(-7 * 3600)
        let collectionMetaId = "\(username)_collection_\(DiscogsConstants.allFolderId)"
        let wantlistMetaId = "\(username)_wantlist"

        let cMeta = CachedFetchMetadata(id: collectionMetaId, lastFetchedAt: sevenHoursAgo)
        context.insert(cMeta)

        let wMeta = CachedFetchMetadata(id: wantlistMetaId, lastFetchedAt: sevenHoursAgo)
        context.insert(wMeta)

        try? context.save()
    }

    /// Réinitialise l'horodatage du cache à l'instant présent (tout frais).
    func resetCacheFreshness(username: String) {
        let now = Date()
        let collectionMetaId = "\(username)_collection_\(DiscogsConstants.allFolderId)"
        let wantlistMetaId = "\(username)_wantlist"

        let cMeta = CachedFetchMetadata(id: collectionMetaId, lastFetchedAt: now)
        context.insert(cMeta)

        let wMeta = CachedFetchMetadata(id: wantlistMetaId, lastFetchedAt: now)
        context.insert(wMeta)

        try? context.save()
    }

    // MARK: - Wantlist

    /// Synchronisation complète : purge d'abord toute entrée en cache qui ne fait plus partie
    /// de `fullItems` (voir `syncCollectionFolder`, même logique) — contrairement à
    /// `saveWantlistItems`, purement additif, qui ne supprime jamais les entrées obsolètes.
    /// Sans cette purge, une release retirée de la wantlist par un autre moyen que Spinlog (ou
    /// dont la suppression locale a échoué une fois) reste indéfiniment fantôme dans le cache et
    /// continue de s'afficher comme "en wantlist" ailleurs dans l'app (résultats de recherche,
    /// bouton sur la fiche release) via `LibraryMembershipStore.refresh()`.
    /// À appeler uniquement quand `fullItems` représente l'intégralité de la wantlist distante
    /// (toutes les pages chargées), jamais une page partielle.
    func syncWantlist(username: String, fullItems: [WantlistItem]) {
        let now = Date()
        let encoder = JSONEncoder()

        let deleteDescriptor = FetchDescriptor<CachedWantlistEntry>(
            predicate: #Predicate<CachedWantlistEntry> { $0.username == username }
        )
        if let oldEntries = try? context.fetch(deleteDescriptor) {
            for entry in oldEntries {
                context.delete(entry)
            }
        }

        for item in fullItems {
            guard let data = try? encoder.encode(item) else { continue }
            let entry = CachedWantlistEntry(
                username: username,
                releaseId: item.id,
                payload: data,
                lastFetchedAt: now
            )
            context.insert(entry)
        }

        let metaId = "\(username)_wantlist"
        let meta = CachedFetchMetadata(id: metaId, lastFetchedAt: now)
        context.insert(meta)

        try? context.save()
    }

    func saveWantlistItems(_ items: [WantlistItem], username: String) async {
        let now = Date()
        let encoder = JSONEncoder()

        for (index, item) in items.enumerated() {
            guard let data = try? encoder.encode(item) else { continue }
            let entry = CachedWantlistEntry(
                username: username,
                releaseId: item.id,
                payload: data,
                lastFetchedAt: now
            )
            context.insert(entry)
            await saveAndYieldIfNeeded(index)
        }

        let metaId = "\(username)_wantlist"
        let meta = CachedFetchMetadata(id: metaId, lastFetchedAt: now)
        context.insert(meta)

        try? context.save()
    }

    /// Remplace tout le cache wantlist du compte par `items`, à n'appeler qu'avec la liste
    /// complète : contrairement à `saveWantlistItems` (qui ne fait qu'ajouter/mettre à jour),
    /// supprime aussi les entrées absentes — ex: retirées de la wantlist depuis discogs.com, qui
    /// sinon réapparaissaient hors ligne.
    func replaceWantlistItems(_ items: [WantlistItem], username: String) async {
        let keptReleaseIds = Set(items.map(\.id))
        let descriptor = FetchDescriptor<CachedWantlistEntry>(
            predicate: #Predicate<CachedWantlistEntry> { $0.username == username }
        )
        if let entries = try? context.fetch(descriptor) {
            for (index, entry) in entries.enumerated() where !keptReleaseIds.contains(entry.releaseId) {
                context.delete(entry)
                await saveAndYieldIfNeeded(index)
            }
        }
        await saveWantlistItems(items, username: username)
    }

    /// Identifiants de release présents dans le cache de la collection ("Tous"), sans décoder
    /// les payloads JSON (seul `releaseId` est lu).
    func collectionReleaseIds(username: String) -> Set<Int> {
        let allFolderId = DiscogsConstants.allFolderId
        var descriptor = FetchDescriptor<CachedCollectionEntry>(
            predicate: #Predicate<CachedCollectionEntry> { $0.username == username && $0.folderId == allFolderId }
        )
        descriptor.propertiesToFetch = [\.releaseId]
        return Set(((try? context.fetch(descriptor)) ?? []).map(\.releaseId))
    }

    /// Identifiants de release présents dans le cache de la wantlist, sans décoder les payloads.
    func wantlistReleaseIds(username: String) -> Set<Int> {
        var descriptor = FetchDescriptor<CachedWantlistEntry>(
            predicate: #Predicate<CachedWantlistEntry> { $0.username == username }
        )
        descriptor.propertiesToFetch = [\.releaseId]
        return Set(((try? context.fetch(descriptor)) ?? []).map(\.releaseId))
    }

    /// Payloads JSON bruts de toute la collection en cache (tous dossiers, donc un même
    /// exemplaire peut apparaître plusieurs fois), sans les décoder : à décoder hors du fil
    /// principal par l'appelant, pour ne pas bloquer l'interface sur une grosse collection.
    func collectionPayloads(username: String) -> [Data] {
        var descriptor = FetchDescriptor<CachedCollectionEntry>(
            predicate: #Predicate<CachedCollectionEntry> { $0.username == username }
        )
        descriptor.propertiesToFetch = [\.payload]
        return ((try? context.fetch(descriptor)) ?? []).map(\.payload)
    }

    /// Payloads JSON bruts de toute la wantlist en cache, sans les décoder (voir
    /// `collectionPayloads`).
    func wantlistPayloads(username: String) -> [Data] {
        var descriptor = FetchDescriptor<CachedWantlistEntry>(
            predicate: #Predicate<CachedWantlistEntry> { $0.username == username }
        )
        descriptor.propertiesToFetch = [\.payload]
        return ((try? context.fetch(descriptor)) ?? []).map(\.payload)
    }

    /// Un seul élément de la wantlist en cache, sans décoder toute la wantlist.
    func getWantlistItem(username: String, releaseId: Int) -> WantlistItem? {
        let targetId = "\(username)_\(releaseId)"
        let descriptor = FetchDescriptor<CachedWantlistEntry>(
            predicate: #Predicate<CachedWantlistEntry> { $0.id == targetId }
        )
        guard let entry = (try? context.fetch(descriptor))?.first else { return nil }
        return try? JSONDecoder().decode(WantlistItem.self, from: entry.payload)
    }

    nonisolated private static func decodeWantlistItems(from payloads: [Data]) -> [WantlistItem] {
        let decoder = JSONDecoder()
        return payloads.compactMap { try? decoder.decode(WantlistItem.self, from: $0) }
    }

    func getWantlistItems(username: String) async -> [WantlistItem] {
        let descriptor = FetchDescriptor<CachedWantlistEntry>(
            predicate: #Predicate<CachedWantlistEntry> { $0.username == username }
        )
        guard let entries = try? context.fetch(descriptor) else { return [] }
        let payloads = entries.map(\.payload)
        return await Task.detached(priority: .userInitiated) {
            Self.decodeWantlistItems(from: payloads)
        }.value
    }

    func removeWantlistItem(username: String, releaseId: Int) {
        let targetId = "\(username)_\(releaseId)"
        let descriptor = FetchDescriptor<CachedWantlistEntry>(
            predicate: #Predicate<CachedWantlistEntry> { $0.id == targetId }
        )
        if let entries = try? context.fetch(descriptor) {
            widgetSnapshotLogger.log("LibrarySyncDebug DELETE targetId=\(targetId) matchedEntries=\(entries.count)")
            for entry in entries {
                context.delete(entry)
            }
            let saveError: String
            do {
                try context.save()
                saveError = "none"
            } catch {
                saveError = error.localizedDescription
            }
            widgetSnapshotLogger.log("LibrarySyncDebug DELETE targetId=\(targetId) saveError=\(saveError)")
        } else {
            widgetSnapshotLogger.log("LibrarySyncDebug DELETE targetId=\(targetId) fetchFailed")
        }
    }

    func lastWantlistFetchedAt(username: String) -> Date? {
        let targetId = "\(username)_wantlist"
        let descriptor = FetchDescriptor<CachedFetchMetadata>(
            predicate: #Predicate<CachedFetchMetadata> { $0.id == targetId }
        )
        return (try? context.fetch(descriptor))?.first?.lastFetchedAt
    }

    func isWantlistStale(username: String) -> Bool {
        guard let date = lastWantlistFetchedAt(username: username) else {
            return true
        }
        return Date().timeIntervalSince(date) >= DiscogsConstants.sixHoursTTL
    }

    // MARK: - Dossiers

    func saveFolders(_ folders: [CollectionFolder], username: String) {
        let now = Date()
        let encoder = JSONEncoder()
        for folder in folders {
            guard let data = try? encoder.encode(folder) else { continue }
            let entry = CachedFolderEntry(
                username: username,
                folderId: folder.id,
                payload: data,
                lastFetchedAt: now
            )
            context.insert(entry)
        }
        try? context.save()
    }

    func getFolders(username: String) -> [CollectionFolder] {
        let descriptor = FetchDescriptor<CachedFolderEntry>(
            predicate: #Predicate<CachedFolderEntry> { $0.username == username }
        )
        guard let entries = try? context.fetch(descriptor) else { return [] }
        let decoder = JSONDecoder()
        return entries.compactMap { try? decoder.decode(CollectionFolder.self, from: $0.payload) }
    }

    // MARK: - Suppression complète des données utilisateur (Guideline 5.1.1(v))

    /// Supprime l'intégralité des données en cache pour un utilisateur (collection, wantlist, dossiers, métadonnées).
    func clearAllUserData(username: String) {
        let colDescriptor = FetchDescriptor<CachedCollectionEntry>(
            predicate: #Predicate<CachedCollectionEntry> { $0.username == username }
        )
        if let entries = try? context.fetch(colDescriptor) {
            for entry in entries { context.delete(entry) }
        }

        let wantDescriptor = FetchDescriptor<CachedWantlistEntry>(
            predicate: #Predicate<CachedWantlistEntry> { $0.username == username }
        )
        if let entries = try? context.fetch(wantDescriptor) {
            for entry in entries { context.delete(entry) }
        }

        let folderDescriptor = FetchDescriptor<CachedFolderEntry>(
            predicate: #Predicate<CachedFolderEntry> { $0.username == username }
        )
        if let entries = try? context.fetch(folderDescriptor) {
            for entry in entries { context.delete(entry) }
        }

        let collectionMetaId = "\(username)_collection"
        let wantlistMetaId = "\(username)_wantlist"
        let metaDescriptor = FetchDescriptor<CachedFetchMetadata>(
            predicate: #Predicate<CachedFetchMetadata> { $0.id == collectionMetaId || $0.id == wantlistMetaId }
        )
        if let entries = try? context.fetch(metaDescriptor) {
            for entry in entries { context.delete(entry) }
        }

        try? context.save()
        localDataStoreLogger.info("Données locales SwiftData purgées pour \(username)")
    }
}

extension Notification.Name {
    static let masterYearResolved = Notification.Name("com.spinlog.masterYearResolved")
}
