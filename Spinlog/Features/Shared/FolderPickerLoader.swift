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

    /// Dossiers pour le sélecteur d'une fiche disque. Réutilise d'abord ceux déjà en mémoire dans
    /// `CollectionViewModel` (chargés dès le lancement, voir `RootTabView`) plutôt que de refaire
    /// systématiquement l'appel `GET .../collection/folders` : chaque ouverture de fiche en
    /// appelait sinon une copie indépendante, alors que cette donnée change rarement.
    /// - Returns: `nil` si rien n'a pu être chargé.
    static func foldersForReleasePage(username: String) async -> [CollectionFolder]? {
        let sharedFolders = CollectionViewModel.shared.folders
        if !sharedFolders.isEmpty {
            return sharedFolders
        }
        let result = await loadFolders(
            username: username,
            networkMonitor: .shared,
            localStore: .shared,
            credentials: DiscogsAuthManager.shared.credentials
        )
        guard case .success(let fetched) = result, !fetched.isEmpty else { return nil }
        return fetched
    }
}

extension [CollectionFolder] {
    /// Nom convivial du dossier ; « Uncategorized » ou « Dossier n » s'il n'est pas (encore) connu.
    func name(forFolderId folderId: Int) -> String {
        if let folder = first(where: { $0.id == folderId }) {
            return folder.name
        }
        if folderId == DiscogsConstants.uncategorizedFolderId {
            return "Uncategorized"
        }
        return "Dossier \(folderId)"
    }
}
