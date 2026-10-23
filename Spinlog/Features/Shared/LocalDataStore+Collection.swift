import Foundation
import SwiftData
import WidgetKit
import OSLog

extension LocalDataStore {
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
    func saveAndYieldIfNeeded(_ index: Int) async {
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
        let metaId = CacheMetaKey.collection(username: username, folderId: folderId)
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

        let metaId = CacheMetaKey.collection(username: username, folderId: folderId)
        let meta = CachedFetchMetadata(id: metaId, lastFetchedAt: now)
        context.insert(meta)

        try? context.save()

        // Collection complète et fraîche en cache : moment où les grades peuvent être recomptés.
        if folderId == DiscogsConstants.allFolderId {
            GradeEvaluator.shared.evaluateCollection()
        }

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
        // Une synchro terminée après la déconnexion ne doit pas réafficher dans le widget la
        // collection du compte qu'on vient de quitter (vidé par `DiscogsAuthManager.logout`).
        guard DiscogsAuthManager.shared.isAuthenticated else { return }
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
        let targetId = CacheMetaKey.collection(username: username, folderId: folderId)
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
}
