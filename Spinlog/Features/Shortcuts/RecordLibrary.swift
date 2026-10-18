import Foundation

/// Accès à la collection en cache pour les raccourcis.
enum RecordLibrary {
    /// Disques du compte connecté, un par release, dans l'ordre du cache.
    static func records() async throws -> [RecordEntity] {
        guard let username = DiscogsAuthManager.shared.username else { throw RecordIntentError.notSignedIn }
        let items = await LocalDataStore.shared.getAllCollectionItems(username: username)
        return uniqueRecords(from: items)
    }

    static func recentlyListened(limit: Int) async throws -> [RecordEntity] {
        let all = try await records()
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<Int>()
        var result: [RecordEntity] = []
        for session in ListeningLogStore.shared.sessions where seen.insert(session.releaseId).inserted {
            if let record = byId[session.releaseId] {
                result.append(record)
            }
            if result.count == limit { break }
        }
        return result
    }

    // MARK: - Règles pures (testées dans `RecordLibraryTests`)

    nonisolated static func uniqueRecords(from items: [CollectionItem]) -> [RecordEntity] {
        var seen = Set<Int>()
        return items.compactMap { item in
            guard seen.insert(item.releaseId).inserted else { return nil }
            let info = item.basicInformation
            return RecordEntity(id: item.releaseId, title: info.title, artist: info.artistNames, coverURL: info.coverImage ?? info.thumb)
        }
    }

    /// Recherche insensible à la casse et aux accents, sur le titre et l'artiste ; tous les mots
    /// saisis doivent apparaître (« miles blue » trouve Kind of Blue de Miles Davis).
    nonisolated static func matching(_ query: String, in records: [RecordEntity]) -> [RecordEntity] {
        let words = query
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }
        return records.filter { record in
            let haystack = "\(record.title) \(record.artist)".folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}
