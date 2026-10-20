import Foundation
import Testing
@testable import Spinlog

/// Le serveur de démo répond à la place de Discogs pour le compte d'exemple : ses réponses
/// doivent se décoder avec les modèles réels de l'app, et toute écriture doit être refusée.
@MainActor
struct DemoServerTests {
    private let account = "users/\(DemoMode.username)"
    private let decoder = JSONDecoder()

    private func get<T: Decodable>(_ path: String, _ type: T.Type, query: [URLQueryItem] = []) throws -> T {
        let data = try #require(try DemoServer.response(path: path, method: "GET", queryItems: query))
        return try decoder.decode(T.self, from: data)
    }

    @Test func collectionMixesVinylCDsAndCassettes() throws {
        let response = try get("\(account)/collection/folders/0/releases", CollectionReleasesResponse.self,
                               query: [URLQueryItem(name: "per_page", value: "100")])
        let formats = Set(response.releases.compactMap { $0.basicInformation.formats?.first?.name })
        #expect(formats.isSuperset(of: ["Vinyl", "CD", "Cassette"]))
        #expect(response.releases.allSatisfy { $0.instanceId != $0.releaseId })
    }

    @Test func folderCountsMatchTheirContent() throws {
        let folders = try get("\(account)/collection/folders", CollectionFoldersResponse.self).folders
        let all = try #require(folders.first { $0.id == 0 })
        #expect(folders.filter { $0.id != 0 }.map(\.count).reduce(0, +) == all.count)

        for folder in folders where folder.id != 0 {
            let releases = try get("\(account)/collection/folders/\(folder.id)/releases", CollectionReleasesResponse.self,
                                   query: [URLQueryItem(name: "per_page", value: "100")])
            #expect(releases.releases.count == folder.count, "dossier \(folder.name)")
        }
    }

    @Test func paginatesLikeDiscogs() throws {
        let page1 = try get("\(account)/collection/folders/0/releases", CollectionReleasesResponse.self,
                            query: [URLQueryItem(name: "page", value: "1"), URLQueryItem(name: "per_page", value: "20")])
        let page2 = try get("\(account)/collection/folders/0/releases", CollectionReleasesResponse.self,
                            query: [URLQueryItem(name: "page", value: "2"), URLQueryItem(name: "per_page", value: "20")])
        #expect(page1.releases.count == 20)
        #expect(page1.pagination.pages == page2.pagination.pages)
        #expect(page1.pagination.items == page1.releases.count + page2.releases.count
                || page1.pagination.pages > 2)
        #expect(Set(page1.releases.map(\.instanceId)).isDisjoint(with: page2.releases.map(\.instanceId)))
    }

    @Test func purchasePriceFieldIsDeclaredAndFilled() throws {
        let fields = try get("\(account)/collection/fields", CollectionFieldsResponse.self).fields
        #expect(fields.contains { $0.id == DemoServer.purchasePriceFieldId })
        #expect(fields.contains { $0.id == DemoServer.mediaConditionFieldId && $0.isDropdown })

        let releases = try get("\(account)/collection/folders/0/releases", CollectionReleasesResponse.self,
                               query: [URLQueryItem(name: "per_page", value: "100")]).releases
        let prices = releases.map { $0.value(forFieldId: DemoServer.purchasePriceFieldId) }
        #expect(prices.allSatisfy { PurchasePriceParser.parse($0, defaultCurrency: "EUR") != nil })
    }

    @Test func wantlistAndSingleItemLookups() throws {
        let wants = try get("\(account)/wants", WantlistResponse.self).wants
        let first = try #require(wants.first)
        let item = try get("\(account)/wants/\(first.id)", WantlistItem.self)
        #expect(item.id == first.id)

        #expect(throws: DiscogsAPIClient.APIError.self) {
            _ = try DemoServer.response(path: "\(account)/wants/1", method: "GET", queryItems: [])
        }
    }

    @Test func profileReflectsTheSample() throws {
        let profile = try get(account, DiscogsUserProfile.self)
        let releases = try get("\(account)/collection/folders/0/releases", CollectionReleasesResponse.self,
                               query: [URLQueryItem(name: "per_page", value: "100")]).releases
        #expect(profile.username == DemoMode.username)
        #expect(profile.numCollection == releases.count)
    }

    @Test(arguments: ["POST", "PUT", "DELETE"])
    func writesAreRefused(method: String) {
        #expect {
            _ = try DemoServer.response(path: "\(account)/wants/123", method: method, queryItems: [])
        } throws: { error in
            guard case DiscogsAPIClient.APIError.demoReadOnly = error else { return false }
            return true
        }
    }

    @Test func exampleEstimateIsStableAndMixesGainsAndLosses() {
        let first = DemoServer.exampleMarketEstimate(releaseId: 36307255, purchaseAmount: 32)
        #expect(first == DemoServer.exampleMarketEstimate(releaseId: 36307255, purchaseAmount: 32))
        #expect(first.currency == "EUR")
        #expect(first.staleSince == nil)

        let ratios = (1...13).map { DemoServer.exampleMarketEstimate(releaseId: $0, purchaseAmount: 100).price / 100 }
        #expect(ratios.allSatisfy { (0.75...1.95).contains($0) })
        #expect(ratios.contains { $0 < 1 } && ratios.contains { $0 > 1 })

        let withoutPurchase = DemoServer.exampleMarketEstimate(releaseId: 1234, purchaseAmount: nil).price
        #expect((15...60).contains(withoutPurchase))
    }

    @Test func everyCollectionItemGetsAnExampleEstimate() throws {
        let releases = try get("\(account)/collection/folders/0/releases", CollectionReleasesResponse.self,
                               query: [URLQueryItem(name: "per_page", value: "100")]).releases
        #expect(releases.allSatisfy { DemoServer.exampleMarketEstimate(releaseId: $0.releaseId).price > 0 })
    }

    @Test(arguments: ["2026-01-01T00:30:00Z", "2026-10-20T12:00:00Z", "2026-12-31T23:00:00Z"])
    func exampleListeningFillsMonthAndYearPodiums(nowString: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = try #require(ISO8601DateFormatter().date(from: nowString))
        let releaseIds = Array(100...143)

        let sessions = DemoServer.exampleListeningSessions(releaseIds: releaseIds, now: now, calendar: calendar)
        let startOfMonth = try #require(calendar.date(from: calendar.dateComponents([.year, .month], from: now)))
        let startOfYear = try #require(calendar.date(from: calendar.dateComponents([.year], from: now)))

        #expect(sessions.allSatisfy { $0.timestamp <= now && releaseIds.contains($0.releaseId) })
        #expect(sessions.filter { $0.timestamp >= startOfMonth }.count >= StatsViewModel.minimumListeningSessionsForRanking)
        #expect(sessions.filter { $0.timestamp >= startOfYear }.count >= StatsViewModel.minimumListeningSessionsForRanking)
        #expect(sessions.filter { $0.timestamp < startOfYear }.count > 0)
        #expect(zip(sessions, sessions.dropFirst()).allSatisfy { $0.timestamp >= $1.timestamp })
        // Classement net : le disque le plus écouté devance clairement la moyenne.
        let counts = Dictionary(grouping: sessions, by: \.releaseId).mapValues(\.count)
        #expect((counts.values.max() ?? 0) >= 3 * sessions.count / max(1, counts.count))
    }

    @Test func catalogRequestsGoToDiscogs() throws {
        #expect(try DemoServer.response(path: "releases/2879", method: "GET", queryItems: []) == nil)
        #expect(try DemoServer.response(path: "database/search", method: "GET", queryItems: []) == nil)
        // Un autre compte Discogs (profil public consulté) n'est pas servi par la démo.
        #expect(try DemoServer.response(path: "users/someone_else", method: "GET", queryItems: []) == nil)
    }
}
