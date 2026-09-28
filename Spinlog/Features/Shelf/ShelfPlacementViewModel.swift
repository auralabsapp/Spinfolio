import Foundation

@Observable
@MainActor
final class ShelfPlacementViewModel {
    func neighbors(
        for targetRelease: Release,
        customCollection: [Release]?,
        strategy: ShelfSortStrategy,
        ignoreArticles: Bool,
        username: String?
    ) -> ShelfNeighbors {
        if let customCollection {
            return ShelfPlacementService.findNeighbors(
                for: targetRelease,
                in: customCollection,
                strategy: strategy,
                ignoreArticles: ignoreArticles
            )
        } else {
            return ShelfPlacementService.findNeighborsInLocalStore(
                for: targetRelease,
                username: username,
                strategy: strategy,
                ignoreArticles: ignoreArticles
            )
        }
    }

    /// Précharge l'année originale du master en arrière-plan si la stratégie de tri active en a
    /// besoin et qu'elle n'est pas déjà en cache local.
    func prefetchMasterYearIfNeeded(for release: Release, usesMasterYear: Bool) async {
        guard usesMasterYear,
              let masterId = release.masterId, masterId > 0,
              LocalDataStore.shared.getMasterYear(for: masterId) == nil else { return }

        do {
            let credentials = DiscogsAuthManager.shared.credentials
            let master = try await DiscogsAPIClient.shared.masterRelease(id: masterId, credentials: credentials)
            if let year = master.year, year > 0 {
                LocalDataStore.shared.saveMasterYear(year, for: masterId)
            }
        } catch {}
    }
}
