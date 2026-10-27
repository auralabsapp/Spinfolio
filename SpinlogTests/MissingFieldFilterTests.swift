import Foundation
import Testing
@testable import Spinlog

/// Filtres « Sans prix d'achat » et « Sans état du média » de la Collection.
@MainActor
struct MissingFieldFilterTests {
    private static var nextId = 21_000
    private let priceId = 5
    private let conditionId = 1

    private func item(notes: [(Int, String)]) throws -> CollectionItem {
        Self.nextId += 1
        let json: [String: Any] = [
            "id": Self.nextId, "instance_id": Self.nextId, "folder_id": 1, "rating": 0,
            "date_added": "2024-01-15T10:00:00-07:00",
            "basic_information": ["id": Self.nextId, "title": "Disque", "resource_url": "", "artists": [["id": 1, "name": "Artiste"]]],
            "notes": notes.map { ["field_id": $0.0, "value": $0.1] }
        ]
        return try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func aMissingOrBlankFieldIsEmpty() throws {
        #expect(try item(notes: []).isFieldEmpty(priceId))
        #expect(try item(notes: [(priceId, "")]).isFieldEmpty(priceId))
        #expect(try item(notes: [(priceId, "  \n ")]).isFieldEmpty(priceId))
        #expect(try !item(notes: [(priceId, "20 EUR")]).isFieldEmpty(priceId))
    }

    @Test func onlyTheAskedFieldIsLookedAt() throws {
        let onlyPrice = try item(notes: [(priceId, "20 EUR")])
        #expect(!onlyPrice.isFieldEmpty(priceId))
        #expect(onlyPrice.isFieldEmpty(conditionId))
    }

    @Test func withoutAFilterEverythingMatches() throws {
        #expect(try item(notes: []).matchesLibraryFilters(format: nil, searchText: "", missingFieldIds: []))
        #expect(try item(notes: [(priceId, "20 EUR")]).matchesLibraryFilters(format: nil, searchText: ""))
    }

    @Test func missingPriceKeepsOnlyItemsWithoutPrice() throws {
        let withPrice = try item(notes: [(priceId, "20 EUR"), (conditionId, "VG+")])
        let withoutPrice = try item(notes: [(conditionId, "VG+")])
        #expect(!withPrice.matchesLibraryFilters(format: nil, searchText: "", missingFieldIds: [priceId]))
        #expect(withoutPrice.matchesLibraryFilters(format: nil, searchText: "", missingFieldIds: [priceId]))
    }

    @Test func severalMissingFieldsMustAllBeEmpty() throws {
        let nothing = try item(notes: [])
        let onlyPrice = try item(notes: [(priceId, "20 EUR")])
        let onlyCondition = try item(notes: [(conditionId, "VG+")])
        let ids = [priceId, conditionId]
        #expect(nothing.matchesLibraryFilters(format: nil, searchText: "", missingFieldIds: ids))
        #expect(!onlyPrice.matchesLibraryFilters(format: nil, searchText: "", missingFieldIds: ids))
        #expect(!onlyCondition.matchesLibraryFilters(format: nil, searchText: "", missingFieldIds: ids))
    }

    @Test func missingFieldsCombineWithTheOtherFilters() throws {
        let record = try item(notes: [])
        #expect(record.matchesLibraryFilters(format: nil, searchText: "disque", missingFieldIds: [priceId]))
        #expect(!record.matchesLibraryFilters(format: nil, searchText: "autre", missingFieldIds: [priceId]))
    }

    @Test func filterStateFollowsTheSelectionAndTheConfiguredFields() {
        let display = CollectionDisplayState()
        display.fieldIdProvider = { $0 == .purchasePrice ? 5 : nil }
        display.refreshAvailableMissingFields()
        #expect(display.availableMissingFields == [.purchasePrice])

        display.toggleMissingField(.purchasePrice)
        #expect(display.hasActiveFilters)
        display.clearFilters()
        #expect(!display.hasActiveFilters)

        // Un champ déconfiguré entre-temps sort de la sélection.
        display.toggleMissingField(.purchasePrice)
        display.fieldIdProvider = { _ in nil }
        display.refreshAvailableMissingFields()
        #expect(display.missingFields.isEmpty)
        #expect(display.availableMissingFields.isEmpty)
    }
}
