import Foundation
import Testing
@testable import Spinlog

/// États du disque : correspondance avec les libellés de Discogs, sans jamais deviner.
struct RecordGradeTests {
    @Test func everyGradeIsFoundByItsDiscogsLabel() {
        for grade in RecordGrade.allCases {
            #expect(RecordGrade(discogsValue: grade.discogsLabel) == grade)
        }
    }

    @Test func nameWithoutCodeOrCodeAloneAreAccepted() {
        #expect(RecordGrade(discogsValue: "Near Mint") == .nearMint)
        #expect(RecordGrade(discogsValue: "NM") == .nearMint)
        #expect(RecordGrade(discogsValue: "M-") == .nearMint)
        #expect(RecordGrade(discogsValue: "VG+") == .veryGoodPlus)
        #expect(RecordGrade(discogsValue: "very good") == .veryGood)
        #expect(RecordGrade(discogsValue: "  mint  ") == .mint)
        #expect(RecordGrade(discogsValue: "G+") == .goodPlus)
        #expect(RecordGrade(discogsValue: "P") == .poor)
    }

    @Test func unknownOrEmptyValuesAreNeverGuessed() {
        #expect(RecordGrade(discogsValue: "") == nil)
        #expect(RecordGrade(discogsValue: "   ") == nil)
        #expect(RecordGrade(discogsValue: "Neuf") == nil)
        #expect(RecordGrade(discogsValue: "Excellent") == nil)
        #expect(RecordGrade(discogsValue: "Very") == nil)
    }

    @Test func noSpellingDesignatesTwoGrades() {
        // Chaque grade est reconnu par ses propres écritures seulement.
        for grade in RecordGrade.allCases {
            let matches = RecordGrade.allCases.filter { RecordGrade(discogsValue: grade.discogsLabel) == $0 }
            #expect(matches == [grade])
        }
    }
}

/// Prix d'achat et état du disque gardés dans l'app : lecture, écriture, reprise des valeurs
/// Discogs, isolation par compte. `UserDefaults` dédié à chaque test.
@MainActor
final class CopyDetailsStoreTests {
    private let suite = "CopyDetailsStoreTests-\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let priceFieldId = 5
    private let conditionFieldId = 1

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    deinit {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func makeStore(username: String = "alice", mapped: Bool = true) -> CopyDetailsStore {
        let store = CopyDetailsStore(defaults: defaults)
        store.setActiveUsername(username)
        if mapped { store.applyMapping(price: priceFieldId, condition: conditionFieldId) }
        return store
    }

    private func item(instanceId: Int, notes: [(Int, String)] = []) throws -> CollectionItem {
        let json: [String: Any] = [
            "id": instanceId + 1_000_000, "instance_id": instanceId, "folder_id": 1, "rating": 0,
            "date_added": "2024-01-15T10:00:00-07:00",
            "basic_information": ["id": instanceId + 1_000_000, "title": "Album", "resource_url": "", "artists": [["id": 1, "name": "Artiste"]]],
            "notes": notes.map { ["field_id": $0.0, "value": $0.1] }
        ]
        return try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func priceAndConditionAreKeptPerCopy() {
        let store = makeStore()
        store.setPurchasePrice((24.99, "USD"), for: 11)
        store.setMediaCondition(.veryGoodPlus, for: 11)
        #expect(store.purchasePrice(for: 11)?.amount == 24.99)
        #expect(store.purchasePrice(for: 11)?.currency == "USD")
        #expect(store.mediaCondition(for: 11) == .veryGoodPlus)
        #expect(store.details(for: 12) == nil)
    }

    @Test func clearingAValueKeepsTheEntryEmpty() {
        let store = makeStore()
        store.setPurchasePrice((10, "EUR"), for: 11)
        store.setPurchasePrice(nil, for: 11)
        #expect(store.purchasePrice(for: 11) == nil)
        #expect(store.details(for: 11) != nil)
    }

    @Test func dataSurvivesAReloadAndStaysPerAccount() {
        let alice = makeStore(username: "alice")
        alice.setPurchasePrice((30, "EUR"), for: 11)

        let reloaded = makeStore(username: "alice")
        #expect(reloaded.purchasePrice(for: 11)?.amount == 30)

        let bob = makeStore(username: "bob")
        #expect(bob.purchasePrice(for: 11) == nil)

        alice.setActiveUsername(nil)
        #expect(alice.entries.isEmpty)
        alice.setActiveUsername("ALICE ")
        #expect(alice.purchasePrice(for: 11)?.amount == 30)
    }

    @Test func clearingAnAccountRemovesItsData() {
        let store = makeStore()
        store.setMediaCondition(.good, for: 11)
        store.clearAccountData(for: "alice")
        #expect(store.entries.isEmpty)
        #expect(makeStore().entries.isEmpty)
    }

    @Test func associatedFieldsShowTheValueKeptInTheApp() {
        let store = makeStore()
        #expect(store.fieldValue(forFieldId: priceFieldId, instanceId: 11) == nil)
        store.setPurchasePrice((25.5, "EUR"), for: 11)
        #expect(store.fieldValue(forFieldId: priceFieldId, instanceId: 11) == "25.50 EUR")
        #expect(store.fieldValue(forFieldId: conditionFieldId, instanceId: 11) == "")
        store.setMediaCondition(.nearMint, for: 11)
        #expect(store.fieldValue(forFieldId: conditionFieldId, instanceId: 11) == "Near Mint (NM or M-)")
        #expect(store.fieldValue(forFieldId: 99, instanceId: 11) == nil)
    }

    @Test func aFieldValueEquivalentToTheStoredOneIsRecognized() {
        let store = makeStore()
        store.setPurchasePrice((25.5, "EUR"), for: 11)
        store.setMediaCondition(.veryGoodPlus, for: 11)
        #expect(store.isFieldValue("25,5 €", equivalentToStoredFor: priceFieldId, instanceId: 11, username: "alice"))
        #expect(store.isFieldValue("25.50 EUR", equivalentToStoredFor: priceFieldId, instanceId: 11, username: "alice"))
        #expect(!store.isFieldValue("30 EUR", equivalentToStoredFor: priceFieldId, instanceId: 11, username: "alice"))
        #expect(store.isFieldValue("VG+", equivalentToStoredFor: conditionFieldId, instanceId: 11, username: "alice"))
        #expect(!store.isFieldValue("Good (G)", equivalentToStoredFor: conditionFieldId, instanceId: 11, username: "alice"))
    }

    @Test func writesToTheAssociatedFieldsAreMirrored() {
        let store = makeStore()
        store.mirrorWrite(fieldId: priceFieldId, value: "12,50 €", instanceId: 11, username: "alice")
        store.mirrorWrite(fieldId: conditionFieldId, value: "VG+", instanceId: 11, username: "alice")
        #expect(store.purchasePrice(for: 11)?.amount == 12.5)
        #expect(store.purchasePrice(for: 11)?.currency == "EUR")
        #expect(store.mediaCondition(for: 11) == .veryGoodPlus)

        // Un autre champ, un autre compte ou un état inconnu ne touchent à rien.
        store.mirrorWrite(fieldId: 99, value: "x", instanceId: 11, username: "alice")
        store.mirrorWrite(fieldId: priceFieldId, value: "99 EUR", instanceId: 11, username: "bob")
        store.mirrorWrite(fieldId: conditionFieldId, value: "Neuf", instanceId: 11, username: "alice")
        #expect(store.purchasePrice(for: 11)?.amount == 12.5)
        #expect(store.mediaCondition(for: 11) == .veryGoodPlus)

        // Une valeur vidée efface.
        store.mirrorWrite(fieldId: priceFieldId, value: "  ", instanceId: 11, username: "alice")
        #expect(store.purchasePrice(for: 11) == nil)
    }

    @Test func discogsValuesAreAdoptedOnceWithoutOverwriting() throws {
        let store = makeStore()
        store.setPurchasePrice((50, "EUR"), for: 21)

        let items = [
            try item(instanceId: 21, notes: [(priceFieldId, "10 EUR")]),
            try item(instanceId: 22, notes: [(priceFieldId, "$24.99"), (conditionFieldId, "Near Mint (NM or M-)")]),
            try item(instanceId: 23, notes: [(priceFieldId, "n'importe quoi"), (conditionFieldId, "Neuf")]),
            try item(instanceId: 24)
        ]
        store.adoptLegacyValues(from: items, username: "alice")

        // Saisie locale existante : jamais écrasée.
        #expect(store.purchasePrice(for: 21)?.amount == 50)
        // Valeurs lisibles : reprises, devise comprise.
        #expect(store.purchasePrice(for: 22)?.amount == 24.99)
        #expect(store.purchasePrice(for: 22)?.currency == "USD")
        #expect(store.mediaCondition(for: 22) == .nearMint)
        // Rien de lisible, ou rien du tout : pas d'entrée.
        #expect(store.details(for: 23) == nil)
        #expect(store.details(for: 24) == nil)

        // Une valeur vidée localement n'est pas reprise une seconde fois.
        store.setPurchasePrice(nil, for: 22)
        store.setMediaCondition(nil, for: 22)
        store.adoptLegacyValues(from: items, username: "alice")
        #expect(store.purchasePrice(for: 22) == nil)
        #expect(store.mediaCondition(for: 22) == nil)
    }

    @Test func adoptionNeedsAnAssociatedFieldAndTheActiveAccount() throws {
        let unmapped = makeStore(mapped: false)
        let withPrice = [try item(instanceId: 31, notes: [(priceFieldId, "10 EUR")])]
        unmapped.adoptLegacyValues(from: withPrice, username: "alice")
        #expect(unmapped.details(for: 31) == nil)

        let store = makeStore()
        store.adoptLegacyValues(from: withPrice, username: "bob")
        #expect(store.details(for: 31) == nil)
    }

    @Test func adoptedValuesLoseAgainstAnyRealEdit() throws {
        let store = makeStore()
        store.adoptLegacyValues(from: [try item(instanceId: 41, notes: [(priceFieldId, "10 EUR")])], username: "alice")
        #expect(store.details(for: 41)?.modifiedAt == .distantPast)
        store.setPurchasePrice((12, "EUR"), for: 41)
        #expect((store.details(for: 41)?.modifiedAt ?? .distantPast) > .distantPast)
    }

    @Test func aTemporaryIdentifierMovesToTheFinalOne() {
        let store = makeStore()
        store.setPurchasePrice((15, "GBP"), for: -7)
        store.remapInstanceId(from: -7, to: 70)
        #expect(store.details(for: -7) == nil)
        #expect(store.purchasePrice(for: 70)?.currency == "GBP")

        store.removeDetails(for: 70)
        #expect(store.details(for: 70) == nil)
    }

    @Test func anUnreadableConditionDoesNotLoseThePrice() throws {
        let json = #"{"purchaseAmount":9.5,"purchaseCurrency":"EUR","mediaCondition":"Inconnu","modifiedAt":0}"#
        let details = try JSONDecoder().decode(CopyDetails.self, from: Data(json.utf8))
        #expect(details.purchasePrice?.amount == 9.5)
        #expect(details.mediaCondition == nil)
    }

}

/// Écriture du prix et de l'état : toujours dans l'app, sur Discogs seulement si un champ y est associé.
@MainActor
final class CopyDetailsWriterTests {
    private let suite = "CopyDetailsWriterTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    deinit {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func item(instanceId: Int) throws -> CollectionItem {
        let json: [String: Any] = [
            "id": instanceId + 1_000_000, "instance_id": instanceId, "folder_id": 1, "rating": 0,
            "date_added": "2024-01-15T10:00:00-07:00",
            "basic_information": ["id": instanceId + 1_000_000, "title": "Album", "resource_url": "", "artists": [["id": 1, "name": "Artiste"]]]
        ]
        return try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func valuesAreKeptLocallyAndNothingIsSentWithoutAnAssociatedField() async throws {
        let store = CopyDetailsStore(defaults: defaults)
        store.setActiveUsername("alice")
        let element = try item(instanceId: 51)

        let priceOutcome = await CopyDetailsWriter.setPurchasePrice((18, "EUR"), for: element, username: "alice", store: store)
        let conditionOutcome = await CopyDetailsWriter.setMediaCondition(.veryGood, for: element, username: "alice", store: store)

        #expect(priceOutcome == nil)
        #expect(conditionOutcome == nil)
        #expect(store.purchasePrice(for: 51)?.amount == 18)
        #expect(store.mediaCondition(for: 51) == .veryGood)
    }

    @Test func anotherAccountIsNeverWritten() async throws {
        let store = CopyDetailsStore(defaults: defaults)
        store.setActiveUsername("alice")
        let element = try item(instanceId: 52)

        _ = await CopyDetailsWriter.setPurchasePrice((18, "EUR"), for: element, username: "bob", store: store)
        #expect(store.details(for: 52) == nil)
    }

    @Test func clearingAValueIsKeptLocally() async throws {
        let store = CopyDetailsStore(defaults: defaults)
        store.setActiveUsername("alice")
        let element = try item(instanceId: 53)

        _ = await CopyDetailsWriter.setPurchasePrice((18, "EUR"), for: element, username: "alice", store: store)
        _ = await CopyDetailsWriter.setPurchasePrice(nil, for: element, username: "alice", store: store)
        #expect(store.purchasePrice(for: 53) == nil)
    }
}
