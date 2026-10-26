import Foundation
import Testing
@testable import Spinlog

/// Possession locale et classement sans requête de la discographie d'un artiste.
@MainActor
struct ArtistLibraryIndexTests {
    private let credit = ArtistCredit(artistId: 7, artistName: "Ghost")

    private func work(_ id: Int, type: String = "master", format: String? = nil, mainRelease: Int? = nil) -> ArtistReleaseItem {
        ArtistReleaseItem(discogsId: id, type: type, title: "Œuvre \(id)", year: 2020, thumb: nil, role: "Main", masterId: nil, format: format, mainRelease: mainRelease)
    }

    private func summary(releaseId: Int, masterId: Int?, artistId: Int, artistName: String, title: String = "Opus", added: String = "2026-01-02T03:04:05-07:00", formats: String = #"[{"name":"Vinyl","descriptions":["LP","Album"]}]"#) throws -> ArtistLibraryPayloadSummary {
            let master = masterId.map { #""master_id":\#($0),"# } ?? ""
            let json = """
            {"id":\(releaseId),"date_added":"\(added)","basic_information":{\(master)"title":"\(title)","thumb":"t\(releaseId)","artists":[{"id":\(artistId),"name":"\(artistName)"}],"formats":\(formats)}}
            """
            return try #require(ArtistLibraryPayloadSummary.decodeAll([Data(json.utf8)]).first)
    }

    private func index(owned: [ArtistLibraryPayloadSummary], wanted: [ArtistLibraryPayloadSummary] = []) -> ArtistLibraryIndex {
        var index = ArtistLibraryIndex()
        index.replace(
            owned: Dictionary(uniqueKeysWithValues: owned.map { ($0.releaseId, ArtistLibraryIndex.Record(summary: $0, credit: credit)) }),
            wanted: Dictionary(uniqueKeysWithValues: wanted.map { ($0.releaseId, ArtistLibraryIndex.Record(summary: $0, credit: credit)) })
        )
        return index
    }

    // MARK: - Rattachement à l'artiste

    @Test func aRecordIsCreditedByArtistIdNotByName() {
        #expect(credit.isCredited(artistIds: [7], artistNames: "Autre nom"))
        // « Ghostface Killah » ne doit pas être rattaché à « Ghost ».
        #expect(!credit.isCredited(artistIds: [99], artistNames: "Ghostface Killah"))
    }

    @Test func nameIsOnlyAFallbackWhenTheEntryHasNoArtistIds() {
        #expect(credit.isCredited(artistIds: [], artistNames: "Ghost"))
        #expect(!credit.isCredited(artistIds: [], artistNames: "Ghostface Killah"))
        #expect(!ArtistCredit(artistId: nil, artistName: nil).isCredited(artistIds: [], artistNames: "Ghost"))
    }

    @Test func onlyThisArtistsRecordsCountAsTitles() throws {
        let mine = try summary(releaseId: 1, masterId: 10, artistId: 7, artistName: "Ghost", title: "Opus Eponymous")
        let other = try summary(releaseId: 2, masterId: 20, artistId: 99, artistName: "Ghostface Killah", title: "Ironman")
        let index = index(owned: [mine, other], wanted: [mine])
        #expect(index.ownedKeys.count == 1)
        #expect(index.wantlistKeys.count == 1)
    }

    // MARK: - Possession d'une œuvre

    @Test func aMasterIsOwnedWhenOneOfItsPressingsIs() throws {
        let pressing = try summary(releaseId: 1, masterId: 10, artistId: 7, artistName: "Ghost")
        let ownership = index(owned: [pressing]).ownership(of: work(10))
        #expect(ownership.isOwned)
        #expect(!ownership.isInWantlist)
        #expect(ownership.destination == .release(1, coverURL: "t1"))
    }

    @Test func theMostRecentlyAddedCopyIsTheDestination() throws {
        let older = try summary(releaseId: 1, masterId: 10, artistId: 7, artistName: "Ghost", added: "2025-01-02T03:04:05-07:00")
        let newer = try summary(releaseId: 2, masterId: 10, artistId: 7, artistName: "Ghost", added: "2026-01-02T03:04:05-07:00")
        #expect(index(owned: [older, newer]).ownership(of: work(10)).destination == .release(2, coverURL: "t2"))
    }

    @Test func aWantedCopyIsUsedWhenNothingIsOwned() throws {
        let wanted = try summary(releaseId: 3, masterId: 10, artistId: 7, artistName: "Ghost")
        let ownership = index(owned: [], wanted: [wanted]).ownership(of: work(10))
        #expect(!ownership.isOwned)
        #expect(ownership.isInWantlist)
        #expect(ownership.destination == .release(3, coverURL: "t3"))
    }

    @Test func anUnownedMasterOpensItsMasterPageButALooseReleaseHasNoDestination() {
        let empty = ArtistLibraryIndex()
        #expect(empty.ownership(of: work(10)).destination == .master(10))
        #expect(empty.ownership(of: work(5, type: "release")).destination == nil)
    }

    @Test func aLooseReleaseIsOwnedOnlyByItsOwnIdentifier() throws {
        let copy = try summary(releaseId: 5, masterId: nil, artistId: 7, artistName: "Ghost")
        let index = index(owned: [copy])
        #expect(index.ownership(of: work(5, type: "release")).isOwned)
        #expect(!index.ownership(of: work(6, type: "release")).isOwned)
    }

    @Test func removingACopyUpdatesTheDerivedIndexes() throws {
        let copy = try summary(releaseId: 1, masterId: 10, artistId: 7, artistName: "Ghost")
        var index = index(owned: [copy])
        index.setOwned(nil, forReleaseId: 1)
        #expect(index.ownedKeys.isEmpty)
        #expect(!index.ownership(of: work(10)).isOwned)
    }

    // MARK: - Classement sans requête

    @Test func aLooseReleaseIsClassifiedFromItsFormat() {
        let release = work(5, type: "release", format: "CD, Single, Promo")
        #expect(ArtistDiscographyRules.immediateCategory(for: release, cachedCategory: nil, localFormatTokens: nil)
            == DiscogsDiscography.category(fromFormatSummary: "CD, Single, Promo"))
        #expect(ArtistDiscographyRules.immediateCategory(for: work(6, type: "release"), cachedCategory: nil, localFormatTokens: nil) == .other)
    }

    @Test func aMasterUsesTheCacheThenALocalPressingThenNeedsARequest() {
        let master = work(10, mainRelease: 99)
        #expect(ArtistDiscographyRules.immediateCategory(for: master, cachedCategory: .compilations, localFormatTokens: ["Vinyl", "LP"]) == .compilations)
        #expect(ArtistDiscographyRules.immediateCategory(for: master, cachedCategory: nil, localFormatTokens: ["Vinyl", "LP", "Album"])
            == DiscogsDiscography.category(fromFormatTokens: ["Vinyl", "LP", "Album"]))
        #expect(ArtistDiscographyRules.immediateCategory(for: master, cachedCategory: nil, localFormatTokens: nil) == nil)
    }

    @Test func localFormatTokensComeFromOwnedThenWantedPressings() throws {
        let owned = try summary(releaseId: 1, masterId: 10, artistId: 7, artistName: "Ghost", formats: "[]")
        let wanted = try summary(releaseId: 2, masterId: 10, artistId: 7, artistName: "Ghost", formats: #"[{"name":"CD","descriptions":["Album"]}]"#)
        #expect(index(owned: [owned], wanted: [wanted]).localFormatTokens(forMasterId: 10) == ["CD", "Album"])
        #expect(index(owned: [owned]).localFormatTokens(forMasterId: 10) == nil)
    }

    // MARK: - Pagination

    @Test func listStateFollowsThePagesAndTheCeiling() {
        typealias State = ArtistDetailViewModel.DiscogsDiscographyState
        #expect(ArtistDiscographyRules.stateAfterPage(1, totalPages: 3, maxPages: 10) == State.loaded(isLoadingMore: true, isTruncated: false))
        #expect(ArtistDiscographyRules.stateAfterPage(3, totalPages: 3, maxPages: 10) == State.loaded(isLoadingMore: false, isTruncated: false))
        #expect(ArtistDiscographyRules.stateAfterPage(10, totalPages: 25, maxPages: 10) == State.loaded(isLoadingMore: false, isTruncated: true))
    }
}
