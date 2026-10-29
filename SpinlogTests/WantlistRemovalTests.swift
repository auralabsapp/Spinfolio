import Foundation
import Testing
@testable import Spinlog

/// Câblage entre la fiche disque (notification de retrait) et la liste de l'onglet Wantlist.
@MainActor
struct WantlistRemovalTests {
    private func wantlistItem(id: Int) throws -> WantlistItem {
        let json: [String: Any] = [
            "id": id, "rating": 0, "date_added": "2026-10-29T18:46:00-07:00",
            "basic_information": ["id": id, "title": "T\(id)", "resource_url": "", "artists": [["id": 1, "name": "A"]]]
        ]
        return try JSONDecoder().decode(WantlistItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func aRemovalNotificationTakesTheItemOutOfTheList() async throws {
        let model = WantlistViewModel.shared
        let item = try wantlistItem(id: 424242)
        NotificationCenter.default.post(name: .wantlistItemAdded, object: nil, userInfo: ["item": item])
        #expect(model.items.contains { $0.id == 424242 })

        NotificationCenter.default.post(name: .wantlistItemRemoved, object: nil, userInfo: ["releaseId": 424242])
        #expect(!model.items.contains { $0.id == 424242 })
    }

    // MARK: - Délai de grâce des retraits (réponses de Discogs en retard)

    @Test func aRecentlyRemovedItemIsDroppedFromALateServerResponse() throws {
        var grace = WantlistRemovalGrace()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        grace.markRemoved(7, at: now)
        let response = [try wantlistItem(id: 7), try wantlistItem(id: 8)]
        #expect(grace.filtered(response, now: now.addingTimeInterval(10)).map(\.id) == [8])
    }

    @Test func theExclusionEndsOnceTheServerNoLongerListsTheItem() throws {
        var grace = WantlistRemovalGrace()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        grace.markRemoved(7, at: now)
        _ = grace.filtered([try wantlistItem(id: 8)], now: now.addingTimeInterval(5))
        // Réintroduit plus tard (nouvel ajout fait ailleurs) : la réponse fait foi.
        #expect(grace.filtered([try wantlistItem(id: 7)], now: now.addingTimeInterval(6)).map(\.id) == [7])
    }

    @Test func theExclusionExpires() throws {
        var grace = WantlistRemovalGrace()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        grace.markRemoved(7, at: now)
        let late = now.addingTimeInterval(WantlistRemovalGrace.duration + 1)
        #expect(grace.filtered([try wantlistItem(id: 7)], now: late).map(\.id) == [7])
    }

    @Test func unmarkingLiftsTheExclusion() throws {
        var grace = WantlistRemovalGrace()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        grace.markRemoved(7, at: now)
        grace.unmark(7)
        #expect(grace.filtered([try wantlistItem(id: 7)], now: now).map(\.id) == [7])
    }
}
