import Foundation
import SwiftData
import OSLog

extension LocalDataStore {
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

        let metaId = CacheMetaKey.wantlist(username: username)
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

        let metaId = CacheMetaKey.wantlist(username: username)
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
        let targetId = CacheMetaKey.wantlist(username: username)
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

    /// Remplace la liste des dossiers du compte : un dossier qui n'existe plus sur Discogs
    /// (supprimé dans l'app ou sur discogs.com) disparaît aussi du cache, au lieu de rester
    /// proposé hors ligne comme destination d'ajout.
    func saveFolders(_ folders: [CollectionFolder], username: String) {
        let now = Date()
        let encoder = JSONEncoder()
        let currentIds = Set(folders.map(\.id))
        let descriptor = FetchDescriptor<CachedFolderEntry>(
            predicate: #Predicate<CachedFolderEntry> { $0.username == username }
        )
        for stale in (try? context.fetch(descriptor)) ?? [] where !currentIds.contains(stale.folderId) {
            context.delete(stale)
        }
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
}
