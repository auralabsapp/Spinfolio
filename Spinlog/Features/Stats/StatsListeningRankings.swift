import Foundation

/// Classements d'écoute sur platine de l'onglet Stats (fonction Premium), calculés par des
/// fonctions pures à partir des sessions et des disques de la collection.
extension StatsViewModel {
    /// Classements et podiums recalculés ensemble à chaque changement des écoutes ou de la
    /// collection (voir `recomputeListeningStats`).
    struct ListeningRankings {
        var topAlbums: [TopAlbumEntry] = []
        var topArtists: [TopArtistEntry] = []
        var monthlyPodium: [TopAlbumEntry] = []
        var yearlyPodium: [TopAlbumEntry] = []
    }

    var totalListeningSessionsCount: Int {
        ListeningLogStore.shared.sessions.count
    }

    /// Nombre d'écoutes enregistrées depuis le début du mois calendaire en cours.
    var monthlyListeningSessionsCount: Int {
        Self.sessions(ListeningLogStore.shared.sessions, since: Self.startOfMonth(containing: Date())).count
    }

    /// Nombre d'écoutes enregistrées depuis le début de l'année civile en cours.
    var yearlyListeningSessionsCount: Int {
        Self.sessions(ListeningLogStore.shared.sessions, since: Self.startOfYear(containing: Date())).count
    }

    /// Chaque classement n'est rempli qu'à partir de `minimumListeningSessionsForRanking` écoutes
    /// sur sa période (toujours, mois en cours, année en cours) : en dessous, il n'est pas jugé
    /// représentatif. Les podiums gardent les 3 premiers albums.
    static func listeningRankings(
        sessions: [ListeningSession],
        releases: [Int: CollectionItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ListeningRankings {
        var rankings = ListeningRankings()
        if sessions.count >= minimumListeningSessionsForRanking {
            rankings.topAlbums = rankedAlbums(sessions: sessions, releases: releases)
            rankings.topArtists = rankedArtists(sessions: sessions, releases: releases)
        }
        let thisMonth = Self.sessions(sessions, since: startOfMonth(containing: now, calendar: calendar))
        if thisMonth.count >= minimumListeningSessionsForRanking {
            rankings.monthlyPodium = Array(rankedAlbums(sessions: thisMonth, releases: releases).prefix(3))
        }
        let thisYear = Self.sessions(sessions, since: startOfYear(containing: now, calendar: calendar))
        if thisYear.count >= minimumListeningSessionsForRanking {
            rankings.yearlyPodium = Array(rankedAlbums(sessions: thisYear, releases: releases).prefix(3))
        }
        return rankings
    }

    /// Albums par nombre d'écoutes décroissant, puis par titre ; une écoute d'un disque qui n'est
    /// plus dans la collection est ignorée.
    static func rankedAlbums(sessions: [ListeningSession], releases: [Int: CollectionItem]) -> [TopAlbumEntry] {
        var counts: [Int: Int] = [:]
        for session in sessions {
            counts[session.releaseId, default: 0] += 1
        }
        return counts.compactMap { releaseId, count -> TopAlbumEntry? in
            guard let item = releases[releaseId] else { return nil }
            return TopAlbumEntry(item: item, playCount: count)
        }
        .sorted { $0.playCount != $1.playCount ? $0.playCount > $1.playCount : $0.item.basicInformation.title < $1.item.basicInformation.title }
    }

    /// Artistes dont les disques cumulent le plus d'écoutes, tous exemplaires confondus (ex.
    /// « Miles Davis : 27 sessions réparties sur 3 disques »), suffixe d'homonymie ignoré.
    static func rankedArtists(sessions: [ListeningSession], releases: [Int: CollectionItem]) -> [TopArtistEntry] {
        var playsByArtist: [String: Int] = [:]
        var releasesByArtist: [String: Set<Int>] = [:]
        var discogsArtistsByName: [String: [ReleaseArtist]] = [:]

        for session in sessions {
            guard let item = releases[session.releaseId] else { continue }
            let artist = ArtistShelfSortHelper.cleanDiscogsSuffix(item.basicInformation.artistNames)
            guard !artist.isEmpty else { continue }
            playsByArtist[artist, default: 0] += 1
            releasesByArtist[artist, default: []].insert(session.releaseId)
            if discogsArtistsByName[artist] == nil {
                discogsArtistsByName[artist] = item.basicInformation.artists ?? []
            }
        }

        return playsByArtist.map { name, totalPlays in
            TopArtistEntry(
                name: name,
                totalPlays: totalPlays,
                releaseCount: releasesByArtist[name]?.count ?? 0,
                artists: discogsArtistsByName[name] ?? []
            )
        }
        .sorted { $0.totalPlays != $1.totalPlays ? $0.totalPlays > $1.totalPlays : $0.name < $1.name }
    }

    /// Sessions à partir de `start` ; aucune si la date de début n'a pas pu être calculée.
    static func sessions(_ sessions: [ListeningSession], since start: Date?) -> [ListeningSession] {
        guard let start else { return [] }
        return sessions.filter { $0.timestamp >= start }
    }

    static func startOfMonth(containing date: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))
    }

    static func startOfYear(containing date: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(from: calendar.dateComponents([.year], from: date))
    }
}
