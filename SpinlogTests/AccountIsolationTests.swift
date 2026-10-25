import Foundation
import Testing
@testable import Spinlog

/// Isolation entre comptes et démo : cache des champs personnalisés par compte, fusion de la
/// wantlist sans doublon.
@MainActor
struct AccountIsolationTests {
    private func field(id: Int, name: String) throws -> CollectionField {
        let json: [String: Any] = ["id": id, "name": name, "type": "textarea"]
        return try JSONDecoder().decode(CollectionField.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func want(id: Int, title: String) throws -> WantlistItem {
        let json: [String: Any] = [
            "id": id, "rating": 0, "date_added": "2024-01-15T10:00:00-07:00",
            "basic_information": [
                "id": id, "title": title, "resource_url": "",
                "artists": [["id": 1, "name": "Artiste"]]
            ] as [String: Any]
        ]
        return try JSONDecoder().decode(WantlistItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    // MARK: - Cache des champs personnalisés

    @Test func fieldsAreCachedPerAccount() throws {
        var cache = CollectionFieldsCache()
        cache.store([try field(id: 1, name: "Prix d'achat")], for: "alice")

        #expect(cache.fields(for: "alice")?.map(\.id) == [1])
        // Un autre compte (ou la démo) ne reçoit pas les champs d'alice.
        #expect(cache.fields(for: "bob") == nil)
    }

    @Test func accountNameIsCaseAndSpaceInsensitive() throws {
        var cache = CollectionFieldsCache()
        cache.store([try field(id: 2, name: "État")], for: " Alice ")
        #expect(cache.fields(for: "alice")?.map(\.id) == [2])
    }

    @Test func emptyFieldListIsNotTreatedAsCached() {
        var cache = CollectionFieldsCache()
        cache.store([], for: "alice")
        #expect(cache.fields(for: "alice") == nil)
    }

    @Test func removeAllForgetsEveryAccount() throws {
        var cache = CollectionFieldsCache()
        cache.store([try field(id: 1, name: "A")], for: "alice")
        cache.store([try field(id: 2, name: "B")], for: "bob")
        cache.removeAll()
        #expect(cache.fields(for: "alice") == nil)
        #expect(cache.fields(for: "bob") == nil)
    }

    // MARK: - Fusion de la wantlist

    @Test func mergeRemovesDuplicatesAndKeepsPrimaryVersion() throws {
        let primary = [try want(id: 1, title: "Primaire"), try want(id: 2, title: "Deux")]
        let secondary = [try want(id: 1, title: "Ancienne"), try want(id: 3, title: "Trois")]

        let merged = WantlistViewModel.mergedWantlistItems(primary: primary, secondary: secondary)

        #expect(merged.map(\.id) == [1, 2, 3])
        #expect(merged.first?.basicInformation.title == "Primaire")
    }

    @Test func nextPageAlreadyShownIsNotDuplicated() throws {
        // Après un rechargement de la page 1 fusionnée avec l'affichage, la page 2 renvoyée par
        // Discogs peut contenir des disques déjà présents.
        let shown = [try want(id: 1, title: "A"), try want(id: 2, title: "B")]
        let page2 = [try want(id: 2, title: "B"), try want(id: 4, title: "D")]

        let merged = WantlistViewModel.mergedWantlistItems(primary: shown, secondary: page2)

        #expect(merged.map(\.id) == [1, 2, 4])
    }
}
