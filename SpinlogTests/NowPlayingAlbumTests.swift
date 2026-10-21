import Foundation
import Testing
@testable import Spinlog

/// Fenêtre de lecture plein écran : ligne « genre · année » et choix de la piste voisine.
@MainActor
struct NowPlayingAlbumTests {
    private func track(_ position: String, _ title: String, heading: Bool = false) throws -> Track {
        var json: [String: Any] = ["position": position, "title": title]
        if heading { json["type_"] = "heading" }
        return try JSONDecoder().decode(Track.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func detailLineJoinsGenreAndYear() {
        #expect(NowPlayingAlbum.detailLine(genres: ["Rock", "Pop"], year: 2026) == "Rock · 2026")
        #expect(NowPlayingAlbum.detailLine(genres: nil, year: 1999) == "1999")
        #expect(NowPlayingAlbum.detailLine(genres: ["Jazz"], year: 0) == "Jazz")
        #expect(NowPlayingAlbum.detailLine(genres: [], year: nil) == nil)
    }

    @Test func adjacentTrackSkipsHeadingsAndUnplayableTracks() throws {
        let tracks = [
            try track("", "Face A", heading: true),
            try track("A1", "Un"),
            try track("A2", "Deux"),
            try track("", "Face B", heading: true),
            try track("B1", "Trois")
        ]
        let second = tracks[2].id
        // Suivante : l'intitulé « Face B » est sauté.
        #expect(NowPlayingAlbum.adjacentTrack(in: tracks, from: second, offset: 1) { _ in true }?.title == "Trois")
        // Précédente.
        #expect(NowPlayingAlbum.adjacentTrack(in: tracks, from: second, offset: -1) { _ in true }?.title == "Un")
        // Une piste sans correspondance Apple Music est sautée.
        #expect(NowPlayingAlbum.adjacentTrack(in: tracks, from: tracks[1].id, offset: 1) { $0.title != "Deux" }?.title == "Trois")
    }

    @Test func adjacentTrackStopsAtAlbumEdges() throws {
        let tracks = [try track("1", "Premier"), try track("2", "Dernier")]
        #expect(NowPlayingAlbum.adjacentTrack(in: tracks, from: tracks[0].id, offset: -1) { _ in true } == nil)
        #expect(NowPlayingAlbum.adjacentTrack(in: tracks, from: tracks[1].id, offset: 1) { _ in true } == nil)
        #expect(NowPlayingAlbum.adjacentTrack(in: tracks, from: "inconnu", offset: 1) { _ in true } == nil)
    }
}
