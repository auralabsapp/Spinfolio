import Foundation
import Testing
@testable import Spinlog

@MainActor
struct TagMergeLogicTests {
    private func tag(_ name: String, _ secondsSinceReference: TimeInterval) -> SyncedTag {
        SyncedTag(name: name, addedAt: Date(timeIntervalSinceReferenceDate: secondsSinceReference))
    }

    @Test func unionIsCaseInsensitiveAndKeepsOldestDate() {
        let merged = TagMergeLogic.merge(
            local: [tag("Jazz", 200), tag("Live", 100)],
            remote: [tag("jazz", 50), tag("Promo", 300)]
        )

        #expect(merged.map(\.name) == ["jazz", "Live", "Promo"])
        #expect(merged.first?.addedAt == Date(timeIntervalSinceReferenceDate: 50))
    }

    @Test func emptySidesReturnTheOtherSide() {
        let tags = [tag("A", 1), tag("B", 2)]
        #expect(TagMergeLogic.merge(local: tags, remote: []) == tags)
        #expect(TagMergeLogic.merge(local: [], remote: tags) == tags)
    }

    @Test func truncationKeepsMostRecentTags() {
        let limit = TagConstants.maxTagsPerInstance
        let local = (0..<limit).map { tag("local\($0)", TimeInterval($0)) }
        let remote = [tag("newest", 10_000)]

        let merged = TagMergeLogic.merge(local: local, remote: remote)

        #expect(merged.count == limit)
        #expect(merged.last?.name == "newest")
        #expect(!merged.contains { $0.name == "local0" })
    }
}

@MainActor
struct PurchasePriceParserTests {
    @Test(arguments: [
        ("25,50 €", 25.5, "EUR"),
        ("1.234,56 €", 1234.56, "EUR"),
        ("$1,234.56", 1234.56, "USD"),
        ("$960.00", 960.0, "USD"),
        ("USD 30", 30.0, "USD"),
        ("£12", 12.0, "GBP"),
        ("12.5", 12.5, "CHF")
    ])
    func parsesAmountAndCurrency(raw: String, amount: Double, currency: String) throws {
        let result = try #require(PurchasePriceParser.parse(raw, defaultCurrency: "CHF"))
        #expect(abs(result.amount - amount) < 0.001)
        #expect(result.currency == currency)
    }

    @Test(arguments: ["", "   ", "gratuit"])
    func rejectsInputWithoutAmount(raw: String) {
        #expect(PurchasePriceParser.parse(raw, defaultCurrency: "EUR") == nil)
    }

    @Test func canonicalStringUsesTwoDecimalsAndUppercasedCurrency() {
        #expect(PurchasePriceParser.canonicalString(amount: 25.5, currency: "eur") == "25.50 EUR")
    }
}

@MainActor
struct PendingActionOwnershipTests {
    @Test func legacyActionWithoutOwnerBelongsToAnyAccount() {
        let action = PendingAction(type: .addToWantlist, releaseId: 1)
        #expect(action.belongs(to: "alice"))
    }

    @Test func ownerComparisonIsCaseInsensitive() {
        var action = PendingAction(type: .addToWantlist, releaseId: 1)
        action.username = "Alice"
        #expect(action.belongs(to: "alice"))
        #expect(!action.belongs(to: "bob"))
    }

    @Test func ownerSurvivesPersistenceRoundTrip() throws {
        var action = PendingAction(type: .removeFromCollection, releaseId: 42, folderId: 1, instanceId: 7)
        action.username = "alice"

        let decoded = try JSONDecoder().decode(PendingAction.self, from: JSONEncoder().encode(action))

        #expect(decoded.username == "alice")
        #expect(decoded.instanceId == 7)
    }

    @Test func actionsPersistedBeforeOwnershipStillDecode() throws {
        // Format écrit par les versions antérieures, sans le champ `username`.
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","type":"addToWantlist","releaseId":5,"date":0,"retryCount":0}
        """
        let decoded = try JSONDecoder().decode(PendingAction.self, from: Data(legacyJSON.utf8))

        #expect(decoded.username == nil)
        #expect(decoded.belongs(to: "anyone"))
    }
}

@MainActor
struct DiscogsDiscographyTests {
    private func item(
        _ id: Int,
        _ type: String,
        year: Int?,
        role: String? = "Main",
        masterId: Int? = nil
    ) -> ArtistReleaseItem {
        ArtistReleaseItem(discogsId: id, type: type, title: "\(type) \(id)", year: year, thumb: nil, role: role, masterId: masterId)
    }

    @Test func keepsOnlyMainRole() {
        let works = DiscogsDiscography.mainWorks(from: [
            item(1, "master", year: 2000),
            item(2, "master", year: 2001, role: "Appearance"),
            item(3, "release", year: 2002, role: "TrackAppearance"),
            item(4, "release", year: 2003, role: "Producer"),
            item(5, "release", year: 2004, role: nil)
        ])
        #expect(works.map(\.discogsId) == [1])
    }

    @Test func keepsMastersAndOnlyOrphanReleases() {
        let works = DiscogsDiscography.mainWorks(from: [
            item(10, "master", year: 1990),
            item(11, "release", year: 1995, masterId: 10),
            item(12, "release", year: 1996),
            item(13, "label", year: 1997)
        ])
        #expect(works.map(\.id) == ["release-12", "master-10"])
    }

    @Test func sortsByYearDescendingWithUnknownYearsLast() {
        let works = DiscogsDiscography.mainWorks(from: [
            item(1, "master", year: nil),
            item(2, "master", year: 1985),
            item(3, "master", year: 0),
            item(4, "master", year: 2010),
            item(5, "master", year: 1985)
        ])
        // Ordre d'origine conservé à année égale (2 avant 5) et entre années inconnues (1 avant 3).
        #expect(works.map(\.discogsId) == [4, 2, 5, 1, 3])
    }

    @Test func removesDuplicatesAcrossPages() {
        let works = DiscogsDiscography.mainWorks(from: [
            item(7, "master", year: 2000),
            item(7, "master", year: 2000),
            item(7, "release", year: 2000)
        ])
        // Un master et une release peuvent partager un même identifiant numérique.
        #expect(works.map(\.id) == ["master-7", "release-7"])
    }

    @Test(arguments: [
        // Formats réels relevés sur l'API (pressages principaux de masters Nirvana).
        (["Vinyl", "LP", "Album", "Limited Edition"], DiscogsWorkCategory.albums),
        (["Vinyl", "7\"", "45 RPM", "Single", "Stereo"], DiscogsWorkCategory.singlesAndEPs),
        (["Vinyl", "LP", "Compilation"], DiscogsWorkCategory.compilations),
        (["CD", "EP"], DiscogsWorkCategory.singlesAndEPs),
        (["CD", "Mini-Album"], DiscogsWorkCategory.albums),
        (["Vinyl", "LP"], DiscogsWorkCategory.albums),
        (["DVD", "PAL"], DiscogsWorkCategory.other),
        ([String](), DiscogsWorkCategory.other)
    ])
    func classifiesFormatTokens(tokens: [String], expected: DiscogsWorkCategory) {
        #expect(DiscogsDiscography.category(fromFormatTokens: tokens) == expected)
    }

    @Test func classifiesReleaseFormatSummaries() {
        #expect(DiscogsDiscography.category(fromFormatSummary: "CD, Single, Promo") == .singlesAndEPs)
        #expect(DiscogsDiscography.category(fromFormatSummary: "Cass, Promo, CrO") == .other)
        // « Comp » : abréviation de « Compilation » dans les formats résumés.
        #expect(DiscogsDiscography.category(fromFormatSummary: "2xLP, Album, Comp") == .compilations)
        #expect(DiscogsDiscography.category(fromFormatSummary: "12\", Maxi") == .singlesAndEPs)
    }

    @Test func decodesDiscogsPayload() throws {
        let json = Data("""
        {"pagination": {"page": 1, "pages": 3, "per_page": 100, "items": 250},
         "releases": [
           {"id": 42, "type": "master", "title": "Nevermind", "year": 1991, "thumb": "https://example.com/t.jpg", "role": "Main", "main_release": 367084},
           {"id": 43, "type": "release", "title": "Bleach", "role": "Main", "format": "CD, Single, Promo"}
         ]}
        """.utf8)
        let response = try JSONDecoder().decode(ArtistReleasesResponse.self, from: json)
        #expect(response.pagination.pages == 3)
        #expect(response.releases.map(\.id) == ["master-42", "release-43"])
        #expect(response.releases.last?.year == nil)
        #expect(response.releases.last?.masterId == nil)
        #expect(response.releases.first?.mainRelease == 367084)
        #expect(response.releases.last?.format == "CD, Single, Promo")
    }
}
