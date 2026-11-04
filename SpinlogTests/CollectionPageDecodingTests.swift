import Foundation
import Testing
@testable import Spinlog

/// Une page de collection avec un exemplaire atypique ne doit plus vider l'onglet Collection.
@MainActor
struct CollectionPageDecodingTests {
    private static let pagination = #"{"page":1,"pages":1,"per_page":100,"items":3}"#

    private static func release(instanceId: Int, extra: String = "") -> String {
        """
        {"id":10,"instance_id":\(instanceId),"folder_id":1,"rating":0,"date_added":"2024-01-01T00:00:00-08:00",
        "basic_information":{"id":10,"title":"Titre","resource_url":"https://api.discogs.com/releases/10"}\(extra)}
        """
    }

    private func decode(_ json: String) throws -> CollectionReleasesResponse {
        try JSONDecoder().decode(CollectionReleasesResponse.self, from: Data(json.utf8))
    }

    @Test func unreadableItemIsSkippedInsteadOfFailingThePage() throws {
        let broken = #"{"id":11,"instance_id":2}"#
        let json = #"{"pagination":\#(Self.pagination),"releases":[\#(Self.release(instanceId: 1)),\#(broken),\#(Self.release(instanceId: 3))]}"#
        let response = try decode(json)
        #expect(response.releases.map(\.instanceId) == [1, 3])
    }

    @Test func missingSecondaryFieldsFallBackToDefaults() throws {
        let sparse = #"{"id":10,"instance_id":5,"basic_information":{"id":10,"title":"T","resource_url":"u"}}"#
        let response = try decode(#"{"pagination":\#(Self.pagination),"releases":[\#(sparse)]}"#)
        let item = try #require(response.releases.first)
        #expect(item.rating == 0)
        #expect(item.dateAdded.isEmpty)
        #expect(item.folderId == DiscogsConstants.allFolderId)
    }

    @Test func atypicalReleaseSummaryIsStillRead() throws {
        // Titre et lien absents, année en texte, artiste sans identifiant, label au numéro de
        // catalogue numérique, quantité de format en nombre, format illisible au milieu.
        let atypical = #"""
        {"id":12,"instance_id":7,"basic_information":{"id":12,"year":"1998",
        "artists":[{"name":"Artiste"}],"labels":[{"id":3,"name":"Label","catno":1234}],
        "formats":[{"name":"Cassette","qty":1},42,{"name":"CD","qty":"2"}]}}
        """#
        let response = try decode(#"{"pagination":\#(Self.pagination),"releases":[\#(atypical)]}"#)
        let info = try #require(response.releases.first?.basicInformation)
        #expect(info.title.isEmpty)
        #expect(info.resourceURL.isEmpty)
        #expect(info.year == 1998)
        #expect(info.artists?.first?.name == "Artiste")
        #expect(info.artists?.first?.id == 0)
        #expect(info.labels?.first?.catno == "1234")
        #expect(info.formats?.map(\.name) == ["Cassette", "CD"])
        #expect(info.formats?.first?.qty == "1")
    }

    @Test func missingReleasesKeyGivesEmptyPage() throws {
        let response = try decode(#"{"pagination":\#(Self.pagination)}"#)
        #expect(response.releases.isEmpty)
    }
}
