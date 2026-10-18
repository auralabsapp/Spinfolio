import Foundation
import Testing
@testable import Spinlog

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
