import Foundation
import SwiftData
import WidgetKit
import OSLog

let widgetSnapshotLogger = Logger(subsystem: "com.aurelienscarpa.Spinlog", category: "WidgetSnapshotSync")
let localDataStoreLogger = Logger(subsystem: "com.aurelienscarpa.Spinlog", category: "LocalDataStore")

/// Gestionnaire de persistance locale basé sur SwiftData avec règle de TTL de 6 heures.
@MainActor
final class LocalDataStore {
    static let shared = LocalDataStore()

    private let container: ModelContainer
    let context: ModelContext

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

    /// Enregistre un nouveau point d'historique de la valeur globale de la collection du compte, ou
    /// met à jour celui du jour s'il existe déjà (au plus un point par jour et par compte).
    func saveCollectionSnapshot(username: String, currency: String, low: Double, median: Double, high: Double) {
        claimLegacyCollectionSnapshots(for: username)
        let snapshot = CollectionSnapshot(username: username, currency: currency, low: low, median: median, high: high)
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
        CloudSyncEngine.shared.markCollectionSnapshotDirty(dayStamp: snapshot.dayStamp)
    }

    /// Point d'historique le plus récent du compte (pour déterminer si un rafraîchissement est
    /// nécessaire, ou pour afficher la dernière valeur connue).
    func latestCollectionSnapshot(username: String) -> CollectionSnapshot? {
        allCollectionSnapshots(username: username).last
    }

    /// Historique complet du compte, trié chronologiquement, pour le graphique d'évolution.
    func allCollectionSnapshots(username: String) -> [CollectionSnapshot] {
        claimLegacyCollectionSnapshots(for: username)
        let descriptor = FetchDescriptor<CollectionSnapshot>(
            predicate: #Predicate<CollectionSnapshot> { $0.username == username },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Points enregistrés avant la séparation par compte : rattachés une seule fois au premier
    /// compte qui consulte son historique (même principe que la reprise des anciens tags), au
    /// lieu de rester visibles par tous les comptes de l'appareil.
    private func claimLegacyCollectionSnapshots(for username: String) {
        let descriptor = FetchDescriptor<CollectionSnapshot>(
            predicate: #Predicate<CollectionSnapshot> { $0.username == nil }
        )
        guard let legacy = try? context.fetch(descriptor), !legacy.isEmpty else { return }
        for snapshot in legacy {
            snapshot.username = username
            snapshot.id = CollectionSnapshot.identifier(username: username, date: snapshot.date)
        }
        try? context.save()
    }

    // MARK: - Synchronisation iCloud (compte premium)

    /// Jours (`yyyy-MM-dd`) de tous les points d'historique du compte, pour la synchronisation
    /// initiale (même besoin que `TagStore.allTaggedInstanceIds()`).
    func collectionSnapshotDayStamps(username: String) -> [String] {
        allCollectionSnapshots(username: username).map(\.dayStamp)
    }

    /// Point d'historique du compte pour ce jour, pour construire le contenu à envoyer vers iCloud.
    func collectionSnapshot(dayStamp: String, username: String) -> CollectionSnapshot? {
        allCollectionSnapshots(username: username).first { $0.dayStamp == dayStamp }
    }

    /// Applique un point d'historique reçu d'iCloud (ajout ou mise à jour) pour le compte actif de
    /// la synchronisation. N'écrit qu'en local : ne redéclenche pas d'envoi vers CloudKit.
    func applyRemoteCollectionSnapshot(
        username: String,
        date: Date,
        currency: String,
        low: Double,
        median: Double,
        high: Double
    ) {
        let targetId = CollectionSnapshot.identifier(username: username, date: date)
        let descriptor = FetchDescriptor<CollectionSnapshot>(
            predicate: #Predicate<CollectionSnapshot> { $0.id == targetId }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.date = date
            existing.currency = currency
            existing.low = low
            existing.median = median
            existing.high = high
        } else {
            context.insert(CollectionSnapshot(username: username, date: date, currency: currency, low: low, median: median, high: high))
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

    // MARK: - Garde anti-doublon pour une synchronisation complète en cours

    /// Au lancement à froid avec un cache périmé, `StatsViewModel`, `WidgetSnapshotSyncService`,
    /// `CollectionViewModel.startBackgroundSync` et `OfflineDownloadManager` peuvent chacun décider
    /// indépendamment de recharger tout le même dossier ("All") pour le même compte, puisqu'ils
    /// vérifient tous `isCollectionStale` avant qu'aucun n'ait commencé à écrire le résultat — sans
    /// ce verrou, ça peut lancer 3-4 crawls complets concurrents de la même donnée, en concurrence
    /// pour le même quota Discogs.
    private var activeFullCollectionSyncKeys: Set<String> = []

    /// Tente de réserver une synchronisation complète de ce dossier : `false` si une autre est
    /// déjà en cours pour le même compte/dossier (l'appelant doit alors renoncer, le cache sera de
    /// toute façon rafraîchi par celle en cours). Toujours appairé à `endFullCollectionSync`.
    func beginFullCollectionSync(username: String, folderId: Int) -> Bool {
        let key = "\(username)_\(folderId)"
        guard !activeFullCollectionSyncKeys.contains(key) else { return false }
        activeFullCollectionSyncKeys.insert(key)
        return true
    }

    func endFullCollectionSync(username: String, folderId: Int) {
        activeFullCollectionSyncKeys.remove("\(username)_\(folderId)")
    }

    // MARK: - Outils Développeur / Simulation

    /// Simule un cache plus vieux que 6 heures (7h en arrière) pour tester l'apparition
    /// des bandeaux hors ligne et le comportement de synchronisation selon la règle Discogs.
    func simulateStaleCache(username: String) {
        let sevenHoursAgo = Date().addingTimeInterval(-7 * 3600)
        let collectionMetaId = CacheMetaKey.collection(username: username, folderId: DiscogsConstants.allFolderId)
        let wantlistMetaId = CacheMetaKey.wantlist(username: username)

        let cMeta = CachedFetchMetadata(id: collectionMetaId, lastFetchedAt: sevenHoursAgo)
        context.insert(cMeta)

        let wMeta = CachedFetchMetadata(id: wantlistMetaId, lastFetchedAt: sevenHoursAgo)
        context.insert(wMeta)

        try? context.save()
    }

    /// Réinitialise l'horodatage du cache à l'instant présent (tout frais).
    func resetCacheFreshness(username: String) {
        let now = Date()
        let collectionMetaId = CacheMetaKey.collection(username: username, folderId: DiscogsConstants.allFolderId)
        let wantlistMetaId = CacheMetaKey.wantlist(username: username)

        let cMeta = CachedFetchMetadata(id: collectionMetaId, lastFetchedAt: now)
        context.insert(cMeta)

        let wMeta = CachedFetchMetadata(id: wantlistMetaId, lastFetchedAt: now)
        context.insert(wMeta)

        try? context.save()
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

        // Toutes les métadonnées du compte (collection de chaque dossier, wantlist) : l'ancien filtre
        // visait `<compte>_collection`, alors que les clés réelles portent le numéro de dossier
        // (`CacheMetaKey.collection`), si bien qu'elles n'étaient jamais effacées.
        let metaPrefix = "\(username)_"
        if let entries = try? context.fetch(FetchDescriptor<CachedFetchMetadata>()) {
            for entry in entries where entry.id.hasPrefix(metaPrefix) { context.delete(entry) }
        }

        // Historique de la valeur de la collection du compte (montants personnels) : les autres
        // comptes de l'appareil gardent le leur.
        let snapshotDescriptor = FetchDescriptor<CollectionSnapshot>(
            predicate: #Predicate<CollectionSnapshot> { $0.username == username }
        )
        if let snapshots = try? context.fetch(snapshotDescriptor) {
            for snapshot in snapshots { context.delete(snapshot) }
        }

        try? context.save()
        localDataStoreLogger.info("Données locales SwiftData purgées pour \(username)")
    }
}

extension Notification.Name {
    static let masterYearResolved = Notification.Name("com.spinlog.masterYearResolved")
}
