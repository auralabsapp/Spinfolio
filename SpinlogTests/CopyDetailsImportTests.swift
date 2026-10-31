import Foundation
import Testing
@testable import Spinlog

/// Import depuis des champs Discogs : lecture stricte des valeurs, plan chiffré, règles de conflit,
/// annulation.
@MainActor
struct CopyDetailsImportTests {
    private let priceId = 5
    private let conditionId = 1

    // MARK: - Lecture des prix

    @Test(arguments: [
        ("24,99", 24.99, "EUR", false),
        ("24.99", 24.99, "EUR", false),
        ("12", 12, "EUR", false),
        ("0", 0, "EUR", false),
        ("€24.99", 24.99, "EUR", true),
        ("24,99 €", 24.99, "EUR", true),
        ("€ 24,99", 24.99, "EUR", true),
        ("$30.00", 30, "USD", true),
        ("£12.5", 12.5, "GBP", true),
        ("USD 30", 30, "USD", true),
        ("30 usd", 30, "USD", true),
        ("EUR30", 30, "EUR", true),
        ("1 234,56 €", 1234.56, "EUR", true),
        ("1.234,56", 1234.56, "EUR", false),
        ("1,234.56", 1234.56, "EUR", false),
        ("1.234", 1234, "EUR", false),
        ("  18,50  ", 18.5, "EUR", false),
        ("1\u{a0}250 €", 1250, "EUR", true)
    ])
    func readablePricesAreRead(raw: String, amount: Double, currency: String, hasCurrency: Bool) {
        let reading = CopyDetailsImport.readPrice(raw, unspecifiedCurrency: "EUR")
        #expect(reading == .valid(amount: amount, currency: currency, hasCurrency: hasCurrency), "\(raw)")
    }

    @Test(arguments: ["12 euros environ", "3 x 10", "prix 12", "-3", "abc", "12,345,6", "SEK 30", "€ 30 EUR", "20-25", "1.2.3,4", "12 €€"])
    func looseOrOddPricesAreUnreadable(raw: String) {
        #expect(CopyDetailsImport.readPrice(raw, unspecifiedCurrency: "EUR") == .unreadable, "\(raw)")
    }

    @Test func emptyPriceIsEmpty() {
        #expect(CopyDetailsImport.readPrice("", unspecifiedCurrency: "EUR") == .empty)
        #expect(CopyDetailsImport.readPrice("  \n ", unspecifiedCurrency: "EUR") == .empty)
    }

    @Test func theChosenCurrencyAppliesOnlyToPricesWithoutOne() {
        #expect(CopyDetailsImport.readPrice("20", unspecifiedCurrency: "USD") == .valid(amount: 20, currency: "USD", hasCurrency: false))
        #expect(CopyDetailsImport.readPrice("20 €", unspecifiedCurrency: "USD") == .valid(amount: 20, currency: "EUR", hasCurrency: true))
    }

    // MARK: - Lecture des états

    @Test func gradesAreReadOrLeftUnreadable() {
        #expect(CopyDetailsImport.readGrade("Near Mint (NM or M-)") == .valid(.nearMint))
        #expect(CopyDetailsImport.readGrade("vg+") == .valid(.veryGoodPlus))
        #expect(CopyDetailsImport.readGrade("") == .empty)
        #expect(CopyDetailsImport.readGrade("Neuf") == .unreadable)
    }

    // MARK: - Plan

    private func item(instanceId: Int, title: String = "Album", notes: [(Int, String)]) throws -> CollectionItem {
        let json: [String: Any] = [
            "id": instanceId + 1_000_000, "instance_id": instanceId, "folder_id": 1, "rating": 0,
            "date_added": "2024-01-15T10:00:00-07:00",
            "basic_information": ["id": instanceId + 1_000_000, "title": title, "resource_url": "", "artists": [["id": 1, "name": "Artiste"]]],
            "notes": notes.map { ["field_id": $0.0, "value": $0.1] }
        ]
        return try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func samplePlan(existing: [Int: CopyDetails] = [:]) throws -> CopyDetailsImport.Plan {
        let items = [
            try item(instanceId: 1, title: "A", notes: [(priceId, "20 €"), (conditionId, "Near Mint (NM or M-)")]),
            try item(instanceId: 2, title: "B", notes: [(priceId, "12,50"), (conditionId, "Neuf")]),
            try item(instanceId: 3, title: "C", notes: [(priceId, "environ 10")]),
            try item(instanceId: 4, title: "D", notes: []),
            try item(instanceId: 5, title: "E", notes: [(priceId, "$30"), (conditionId, "VG+")]),
            try item(instanceId: 6, title: "F", notes: [(priceId, "9 €")])
        ]
        return CopyDetailsImport.plan(
            items: items, priceFieldId: priceId, conditionFieldId: conditionId,
            unspecifiedCurrency: "EUR", existing: { existing[$0] }
        )
    }

    @Test func thePlanCountsEachCase() throws {
        let plan = try samplePlan(existing: [
            1: CopyDetails(purchaseAmount: 20, purchaseCurrency: "EUR", mediaCondition: .nearMint),
            5: CopyDetails(purchaseAmount: 25, purchaseCurrency: "USD", mediaCondition: .good)
        ])
        // Prix : 1 identique, 5 en conflit (25 → 30 USD) ; 2 et 6 à importer ; 3 illisible ; 4 vide.
        #expect(plan.price.upToDate == 1)
        #expect(plan.price.conflicts == 1)
        #expect(plan.price.toImport == 2)
        #expect(plan.price.unreadable.map(\.instanceId) == [3])
        #expect(plan.price.emptyOnDiscogs == 1)
        // État : 1 identique, 5 en conflit (Good → VG+), 2 illisible (« Neuf »), 3, 4 et 6 vides.
        #expect(plan.condition.upToDate == 1)
        #expect(plan.condition.conflicts == 1)
        #expect(plan.condition.toImport == 0)
        #expect(plan.condition.unreadable.map(\.raw) == ["Neuf"])
        #expect(plan.condition.emptyOnDiscogs == 3)
    }

    @Test func currenciesAreBrokenDownAndUnspecifiedOnesCounted() throws {
        let plan = try samplePlan()
        #expect(plan.currencies["EUR"] == 3)
        #expect(plan.currencies["USD"] == 1)
        #expect(plan.withoutCurrency == 1)
    }

    @Test func samplesShowUpToThreeValuesRead() throws {
        let plan = try samplePlan()
        #expect(plan.samples.count == 3)
        #expect(plan.samples.first?.title == "A")
        #expect(plan.samples.first?.raw == "20 € · Near Mint (NM or M-)")
    }

    @Test func conflictsAreKeptUnlessReplacing() throws {
        let existing = [5: CopyDetails(purchaseAmount: 25, purchaseCurrency: "USD", mediaCondition: .good)]
        let plan = try samplePlan(existing: existing)

        let keeping = plan.operations(replacing: false)
        #expect(keeping.contains { $0.instanceId == 5 } == false)
        #expect(keeping.map(\.instanceId).sorted() == [1, 2, 6])

        let replacing = plan.operations(replacing: true)
        let fifth = try #require(replacing.first { $0.instanceId == 5 })
        #expect(fifth.price?.amount == 30)
        #expect(fifth.grade == .veryGoodPlus)
    }

    @Test func anEmptyOrUnreadableValueNeverErasesALocalOne() throws {
        let existing = [
            3: CopyDetails(purchaseAmount: 10, purchaseCurrency: "EUR"),
            4: CopyDetails(purchaseAmount: 8, purchaseCurrency: "EUR", mediaCondition: .mint)
        ]
        let plan = try samplePlan(existing: existing)
        let all = plan.operations(replacing: true)
        #expect(all.contains { $0.instanceId == 3 } == false)
        #expect(all.contains { $0.instanceId == 4 } == false)
    }

    @Test func identicalValuesProduceNoOperation() throws {
        let existing = [1: CopyDetails(purchaseAmount: 20, purchaseCurrency: "EUR", mediaCondition: .nearMint)]
        let plan = try samplePlan(existing: existing)
        #expect(plan.operations(replacing: true).contains { $0.instanceId == 1 } == false)
    }

    @Test func noFieldChosenMeansNothingToImport() throws {
        let plan = CopyDetailsImport.plan(
            items: [try item(instanceId: 1, notes: [(priceId, "20")])], priceFieldId: nil, conditionFieldId: nil,
            unspecifiedCurrency: "EUR", existing: { _ in nil }
        )
        #expect(plan.isEmpty)
    }

    // MARK: - Application et annulation

    private func makeStore() throws -> (CopyDetailsStore, String) {
        let suite = "CopyDetailsImportTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = CopyDetailsStore(defaults: defaults)
        store.setActiveUsername("alice")
        return (store, suite)
    }

    @Test func applyingAnImportWritesTheValuesAndKeepsAnUndoRecord() throws {
        let (store, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        store.setPurchasePrice((50, "EUR"), for: 5)

        let operations = [
            CopyDetailsImportOperation(instanceId: 5, price: (30, "USD"), grade: .veryGoodPlus),
            CopyDetailsImportOperation(instanceId: 6, price: (9, "EUR"), grade: nil)
        ]
        #expect(store.applyImport(operations) == 2)
        #expect(store.purchasePrice(for: 5)?.amount == 30)
        #expect(store.mediaCondition(for: 5) == .veryGoodPlus)
        #expect(store.purchasePrice(for: 6)?.amount == 9)
        #expect(store.lastImport?.changedCopies == 2)

        #expect(store.undoLastImport() == 2)
        #expect(store.purchasePrice(for: 5)?.amount == 50)
        #expect(store.mediaCondition(for: 5) == nil)
        // Retour à « rien » : une entrée vide et datée (et non l'absence d'entrée), pour que l'annulation
        // se propage aux autres appareils via iCloud.
        #expect(store.details(for: 6)?.isEmpty ?? true)
        #expect(store.lastImport == nil)
    }

    @Test func undoKeepsWhatWasEditedAfterTheImport() throws {
        let (store, suite) = try makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        store.applyImport([CopyDetailsImportOperation(instanceId: 6, price: (9, "EUR"), grade: nil)])
        // Modification faite après l'import : l'annulation ne doit pas la défaire.
        Thread.sleep(forTimeInterval: 0.01)
        store.setPurchasePrice((15, "EUR"), for: 6)
        #expect(store.undoLastImport() == 0)
        #expect(store.purchasePrice(for: 6)?.amount == 15)
    }

    @Test func theUndoRecordSurvivesARelaunchButNotAnAccountChange() throws {
        let suite = "CopyDetailsImportTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let first = CopyDetailsStore(defaults: defaults)
        first.setActiveUsername("alice")
        first.applyImport([CopyDetailsImportOperation(instanceId: 6, price: (9, "EUR"), grade: nil)])

        let relaunched = CopyDetailsStore(defaults: defaults)
        relaunched.setActiveUsername("alice")
        #expect(relaunched.lastImport?.changedCopies == 1)

        relaunched.setActiveUsername("bob")
        #expect(relaunched.lastImport == nil)
    }
}
