import Foundation

/// Délégué vers CollectionPreferencesStore pour compatibilité.
enum LastFolderStore {
    static func lastConsultedFolderId(for username: String) -> Int? {
        CollectionPreferencesStore.lastConsultedFolderId(for: username)
    }

    static func setLastConsultedFolderId(_ folderId: Int?, for username: String) {
        CollectionPreferencesStore.setLastConsultedFolderId(folderId, for: username)
    }
}
