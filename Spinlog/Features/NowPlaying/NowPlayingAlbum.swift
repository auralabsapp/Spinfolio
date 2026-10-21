import Foundation

/// Album affiché par la fenêtre de lecture plein écran (voir `NowPlayingFullScreenView`) : issu
/// d'une release ou d'un master Discogs, selon l'écran d'où la lecture a été lancée.
struct NowPlayingAlbum {
    let title: String
    let artistName: String
    /// « Genre · année », sur le modèle de la page album d'Apple Music.
    let detailLine: String?
    let coverURL: String?
    let tracklist: [Track]

    init(release: Release) {
        title = release.title
        artistName = (release.artists ?? []).map(\.displayName).joined(separator: ", ")
        detailLine = Self.detailLine(genres: release.genres, year: release.year)
        coverURL = release.primaryImageURL
        tracklist = release.tracklist ?? []
    }

    init(master: MasterRelease) {
        title = master.title
        artistName = master.artistNames
        detailLine = Self.detailLine(genres: master.genres, year: master.year)
        coverURL = master.primaryImageURL
        tracklist = master.tracklist ?? []
    }

    static func detailLine(genres: [String]?, year: Int?) -> String? {
        var parts: [String] = []
        if let genre = genres?.first, !genre.isEmpty { parts.append(genre) }
        if let year, year > 0 { parts.append(String(year)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Piste jouable voisine de `trackID` (`offset` +1 : suivante, −1 : précédente). Les intitulés
    /// de section et les pistes sans correspondance Apple Music (`isPlayable` faux) sont sautés :
    /// choisir une piste sans correspondance arrêterait la lecture au lieu de la poursuivre. `nil`
    /// en début ou fin d'album, ou si `trackID` n'est pas dans la liste.
    static func adjacentTrack(
        in tracklist: [Track],
        from trackID: String,
        offset: Int,
        isPlayable: (Track) -> Bool
    ) -> Track? {
        guard offset != 0, let start = tracklist.firstIndex(where: { $0.id == trackID }) else { return nil }
        var index = start + offset
        while tracklist.indices.contains(index) {
            let candidate = tracklist[index]
            if !candidate.isHeading && isPlayable(candidate) { return candidate }
            index += offset
        }
        return nil
    }
}
