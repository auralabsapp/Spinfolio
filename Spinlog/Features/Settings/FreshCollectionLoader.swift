import Foundation

/// Lecture de la collection entière pour les opérations en bloc sur les champs (import depuis
/// Discogs, envoi vers Discogs) : relue sur Discogs quand on est en ligne, cache de moins de 6 h
/// sinon, jamais un cache plus ancien.
@MainActor
enum FreshCollectionLoader {
    /// Toute la collection (dossier « Tous »), `nil` si ni Discogs ni un cache récent ne sont
    /// disponibles.
    static func loadAll(username: String) async -> [CollectionItem]? {
        let localStore = LocalDataStore.shared
        let authManager = DiscogsAuthManager.shared
        let allFolder = DiscogsConstants.allFolderId
        if NetworkMonitor.shared.isConnected, let credentials = authManager.credentials {
            // Relit toujours Discogs, même si le cache est récent : l'utilisateur a pu corriger ses
            // champs sur le site entre deux opérations. Seule une relecture déjà en cours (synchro de
            // fond) fait se rabattre sur le cache.
            if !localStore.beginFullCollectionSync(username: username, folderId: allFolder) {
                return await localStore.getAllCollectionItems(username: username)
            }
            defer { localStore.endFullCollectionSync(username: username, folderId: allFolder) }
            do {
                let all = try await DiscogsAPIClient.shared.fetchAllCollectionItems(
                    username: username,
                    folderId: allFolder,
                    credentials: credentials
                )
                await localStore.syncCollectionFolder(username: username, folderId: allFolder, fullItems: all)
                return all
            } catch {
                guard !localStore.isCollectionStale(username: username, folderId: allFolder) else { return nil }
                return await localStore.getAllCollectionItems(username: username)
            }
        }
        guard !localStore.isCollectionStale(username: username, folderId: allFolder) else { return nil }
        return await localStore.getAllCollectionItems(username: username)
    }
}
