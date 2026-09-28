import Foundation

/// Charge la liste des dossiers à proposer dans un sélecteur "ajouter à la collection" —
/// factorisé car `ReleaseActions` (ajout depuis une fiche release) et `WantlistViewModel`
/// (déplacement wantlist → collection) avaient chacun leur propre copie de cette logique
/// (dossiers réels en ligne, repli sur le cache local ou un dossier "Uncategorized" par défaut
/// hors ligne).
@MainActor
enum FolderPickerLoader {
    static func loadFolders(
        username: String,
        networkMonitor: NetworkMonitor,
        localStore: LocalDataStore,
        credentials: DiscogsCredentials?
    ) async -> Result<[CollectionFolder], Error> {
        if !networkMonitor.isConnected {
            let cached = localStore.getFolders(username: username).filter { $0.id != DiscogsConstants.allFolderId }
            let folders = cached.isEmpty
                ? [CollectionFolder(id: DiscogsConstants.uncategorizedFolderId, name: "Uncategorized", count: 0)]
                : cached
            return .success(folders)
        }

        guard let credentials else { return .success([]) }
        do {
            let response = try await DiscogsAPIClient.shared.collectionFolders(username: username, credentials: credentials)
            return .success(response.folders.filter { $0.id != DiscogsConstants.allFolderId })
        } catch {
            return .failure(error)
        }
    }
}
