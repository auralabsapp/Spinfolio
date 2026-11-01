import Foundation
import Testing
@testable import Spinlog

/// Filtres « Sans prix d'achat » et « Sans état du disque » de la Collection : ils lisent les
/// valeurs gardées dans l'app (`CopyDetailsStore`).
@MainActor
struct MissingFieldFilterTests {
    private static var nextId = 21_000

    private func item() throws -> CollectionItem {
        Self.nextId += 1
        let json: [String: Any] = [
            "id": Self.nextId, "instance_id": Self.nextId, "folder_id": 1, "rating": 0,
            "date_added": "2024-01-15T10:00:00-07:00",
            "basic_information": ["id": Self.nextId, "title": "Album", "resource_url": "", "artists": [["id": 1, "name": "Artiste"]]]
        ]
        return try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// Store partagé activé le temps du test, puis remis dans son état d'origine.
    private func withSharedStore(_ body: (CopyDetailsStore) throws -> Void) rethrows {
        let store = CopyDetailsStore.shared
        let previousUser = store.activeUsername
        store.setActiveUsername("missing-filter-test")
        defer {
            store.clearAccountData(for: "missing-filter-test")
            store.setActiveUsername(previousUser)
        }
        try body(store)
    }

    @Test func anItemWithoutDataIsMissingBothFields() throws {
        try withSharedStore { _ in
            let record = try item()
            #expect(record.isMissing(.purchasePrice))
            #expect(record.isMissing(.mediaCondition))
        }
    }

    @Test func onlyTheAskedFieldIsLookedAt() throws {
        try withSharedStore { store in
            let record = try item()
            store.setPurchasePrice((20, "EUR"), for: record.instanceId)
            #expect(!record.isMissing(.purchasePrice))
            #expect(record.isMissing(.mediaCondition))
        }
    }

    @Test func withoutAFilterEverythingMatches() throws {
        try withSharedStore { store in
            let record = try item()
            #expect(record.matchesLibraryFilters(format: nil, searchText: "", missingFields: []))
            store.setPurchasePrice((20, "EUR"), for: record.instanceId)
            #expect(record.matchesLibraryFilters(format: nil, searchText: ""))
        }
    }

    @Test func missingPriceKeepsOnlyItemsWithoutPrice() throws {
        try withSharedStore { store in
            let withPrice = try item()
            let withoutPrice = try item()
            store.setPurchasePrice((20, "EUR"), for: withPrice.instanceId)
            store.setMediaCondition(.veryGoodPlus, for: withPrice.instanceId)
            store.setMediaCondition(.veryGoodPlus, for: withoutPrice.instanceId)
            #expect(!withPrice.matchesLibraryFilters(format: nil, searchText: "", missingFields: [.purchasePrice]))
            #expect(withoutPrice.matchesLibraryFilters(format: nil, searchText: "", missingFields: [.purchasePrice]))
        }
    }

    @Test func severalMissingFieldsMustAllBeMissing() throws {
        try withSharedStore { store in
            let nothing = try item()
            let onlyPrice = try item()
            let onlyCondition = try item()
            store.setPurchasePrice((20, "EUR"), for: onlyPrice.instanceId)
            store.setMediaCondition(.veryGoodPlus, for: onlyCondition.instanceId)
            let both: Set<LibraryMissingField> = [.purchasePrice, .mediaCondition]
            #expect(nothing.matchesLibraryFilters(format: nil, searchText: "", missingFields: both))
            #expect(!onlyPrice.matchesLibraryFilters(format: nil, searchText: "", missingFields: both))
            #expect(!onlyCondition.matchesLibraryFilters(format: nil, searchText: "", missingFields: both))
        }
    }

    @Test func missingFieldsCombineWithTheOtherFilters() throws {
        try withSharedStore { _ in
            let record = try item()
            #expect(record.matchesLibraryFilters(format: nil, searchText: "album", missingFields: [.purchasePrice]))
            #expect(!record.matchesLibraryFilters(format: nil, searchText: "autre", missingFields: [.purchasePrice]))
        }
    }

    @Test func bothFieldsAreAlwaysOfferedAndFollowTheSelection() {
        let display = CollectionDisplayState()
        #expect(display.availableMissingFields == [.purchasePrice, .mediaCondition])

        display.toggleMissingField(.purchasePrice)
        #expect(display.hasActiveFilters)
        display.clearFilters()
        #expect(!display.hasActiveFilters)
        #expect(display.missingFields.isEmpty)
    }
}
