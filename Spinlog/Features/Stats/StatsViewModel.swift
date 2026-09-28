import Foundation
import Observation

@Observable
@MainActor
final class StatsViewModel {
    private(set) var isLoadingOverview = false
    private(set) var errorMessage: String?

    private(set) var totalCollectionCount: Int?
    private(set) var totalWantlistCount: Int?
    private(set) var recentAdditions: [CollectionItem] = []

    /// Nombre d'ajouts par année, trié chronologiquement — nécessite d'avoir vu toute la
    /// collection au moins une fois (contrairement aux compteurs, qui viennent d'un simple
    /// `pagination.items` sans tout charger).
    private(set) var additionsPerYear: [(year: Int, count: Int)] = []
    private(set) var isLoadingHistogram = false

    /// Estimation globale de la collection, basée sur l'historique réel des ventes Discogs
    /// (`GET /users/{username}/collection/value`) — un seul appel, pas de calcul release par
    /// release côté client.
    private(set) var collectionValue: CollectionValueResponse?
    private(set) var isLoadingValuation = false

    private let authManager = DiscogsAuthManager.shared
    private var histogramTask: Task<Void, Never>?

    /// Compteurs + derniers ajouts : chacun est un seul appel léger (`per_page` réduit), pas
    /// besoin de charger toute la collection pour ça.
    func loadOverview() async {
        guard let username = authManager.username, let credentials = authManager.credentials else { return }
        isLoadingOverview = true
        errorMessage = nil
        do {
            async let collectionCountRequest = DiscogsAPIClient.shared.collectionItems(
                username: username, folderId: 0, page: 1, perPage: 1, credentials: credentials
            )
            async let wantlistCountRequest = DiscogsAPIClient.shared.wantlist(
                username: username, page: 1, perPage: 1, credentials: credentials
            )
            async let recentRequest = DiscogsAPIClient.shared.collectionItems(
                username: username, folderId: 0, page: 1, perPage: 10, sort: "added", sortOrder: "desc", credentials: credentials
            )
            let (collectionResponse, wantlistResponse, recentResponse) = try await (collectionCountRequest, wantlistCountRequest, recentRequest)
            totalCollectionCount = collectionResponse.pagination.items
            totalWantlistCount = wantlistResponse.pagination.items
            recentAdditions = recentResponse.releases
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingOverview = false

        startHistogramLoad()
        await loadValuation()
    }

    private func loadValuation() async {
        guard let username = authManager.username, let credentials = authManager.credentials else { return }
        isLoadingValuation = true
        collectionValue = try? await DiscogsAPIClient.shared.collectionValue(username: username, credentials: credentials)
        isLoadingValuation = false
    }

    /// Parcourt toute la collection (pagination classique, throttlée par `DiscogsAPIClient`)
    /// pour regrouper les dates d'ajout par année — pas d'agrégation côté serveur Discogs.
    private func startHistogramLoad() {
        histogramTask?.cancel()
        guard let username = authManager.username, let credentials = authManager.credentials else { return }
        isLoadingHistogram = true
        histogramTask = Task { [weak self] in
            guard let self else { return }
            var counts: [Int: Int] = [:]
            var page = 1
            var totalPages = 1
            while !Task.isCancelled && page <= totalPages {
                do {
                    let response = try await DiscogsAPIClient.shared.collectionItems(
                        username: username, folderId: 0, page: page, perPage: 100, credentials: credentials
                    )
                    totalPages = response.pagination.pages
                    for item in response.releases {
                        guard let date = item.dateAddedDate else { continue }
                        let year = Calendar.current.component(.year, from: date)
                        counts[year, default: 0] += 1
                    }
                    page += 1
                } catch {
                    break
                }
            }
            guard !Task.isCancelled else { return }
            self.additionsPerYear = counts.sorted { $0.key < $1.key }.map { (year: $0.key, count: $0.value) }
            self.isLoadingHistogram = false
        }
    }
}
