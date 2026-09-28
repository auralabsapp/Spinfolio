import Foundation

/// Ensembles d'identifiants de releases déjà en collection / en wantlist, pour afficher des
/// pastilles dans les listes (résultats de recherche...) sans appel réseau dédié : on relit
/// simplement le cache SwiftData déjà maintenu à jour par les onglets Collection et Wantlist.
@Observable
@MainActor
final class LibraryMembershipStore {
    static let shared = LibraryMembershipStore()

    private(set) var collectionReleaseIds: Set<Int> = []
    private(set) var wantlistReleaseIds: Set<Int> = []

    private let authManager = DiscogsAuthManager.shared
    private let localStore = LocalDataStore.shared

    private init() {}

    /// Recharge les ensembles depuis le cache local. Le dossier `0` correspond au dossier
    /// virtuel Discogs "All", qui agrège l'ensemble de la collection.
    func refresh() {
        guard let username = authManager.username else {
            collectionReleaseIds = []
            wantlistReleaseIds = []
            return
        }
        collectionReleaseIds = Set(localStore.getCollectionItems(username: username, folderId: 0).map(\.releaseId))
        wantlistReleaseIds = Set(localStore.getWantlistItems(username: username).map(\.id))
    }

    func isInCollection(_ releaseId: Int) -> Bool { collectionReleaseIds.contains(releaseId) }
    func isInWantlist(_ releaseId: Int) -> Bool { wantlistReleaseIds.contains(releaseId) }
}
