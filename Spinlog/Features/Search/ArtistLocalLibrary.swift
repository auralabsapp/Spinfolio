import Foundation

/// Lecture de la collection et de la wantlist locales pour la page artiste.
enum ArtistLocalLibrary {
    /// Décode la collection et la wantlist en cache. Le décodage JSON des payloads se fait hors du
    /// fil principal : sur une grosse collection, il figeait l'interface à l'ouverture de la page.
    @MainActor
    static func startDecoding(username: String?) -> Task<([ArtistLibraryPayloadSummary], [ArtistLibraryPayloadSummary]), Never> {
        guard let username else {
            return Task { ([], []) }
        }
        let collectionPayloads = LocalDataStore.shared.collectionPayloads(username: username)
        let wantlistPayloads = LocalDataStore.shared.wantlistPayloads(username: username)
        return Task.detached(priority: .userInitiated) {
            (ArtistLibraryPayloadSummary.decodeAll(collectionPayloads), ArtistLibraryPayloadSummary.decodeAll(wantlistPayloads))
        }
    }

    /// Nom d'un artiste d'après les disques locaux qui le créditent (repli hors ligne).
    static func artistName(id: Int, in summaries: [ArtistLibraryPayloadSummary]) -> String? {
        for summary in summaries {
            if let match = summary.artists.first(where: { $0.id == id }) {
                return match.name
            }
        }
        return nil
    }
}

/// Lecture partielle d'un payload de collection ou de wantlist en cache (même structure JSON
/// pour les deux : `id` = release, `date_added`, `basic_information`), limitée aux champs utiles
/// à la page artiste. `nonisolated` : décodée dans une tâche détachée, hors du fil principal.
nonisolated struct ArtistLibraryPayloadSummary: Decodable, Sendable {
    nonisolated struct Info: Decodable, Sendable {
        nonisolated struct ArtistRef: Decodable, Sendable {
            let id: Int
            let name: String
        }
        nonisolated struct FormatRef: Decodable, Sendable {
            let name: String
            let descriptions: [String]?
        }
        let title: String
        let thumb: String?
        let masterId: Int?
        let artists: [ArtistRef]?
        let formats: [FormatRef]?

        private enum CodingKeys: String, CodingKey {
            case title, thumb, artists, formats
            case masterId = "master_id"
        }
    }

    let releaseId: Int
    let dateAddedRaw: String?
    let info: Info
    /// Renseignée par `decodeAll`, après le décodage JSON.
    var dateAdded: Date?

    var title: String { info.title }
    var thumb: String? { info.thumb }
    var masterId: Int? { info.masterId }
    var artists: [Info.ArtistRef] { info.artists ?? [] }
    var formatTokens: [String] { (info.formats ?? []).flatMap { [$0.name] + ($0.descriptions ?? []) } }
    var artistIds: [Int] { (info.artists ?? []).map(\.id) }
    var artistNames: String { (info.artists ?? []).map(\.name).joined(separator: ", ") }

    private enum CodingKeys: String, CodingKey {
        case releaseId = "id"
        case dateAddedRaw = "date_added"
        case info = "basic_information"
    }

    static func decodeAll(_ payloads: [Data]) -> [ArtistLibraryPayloadSummary] {
        let decoder = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let withoutFraction = ISO8601DateFormatter()
        return payloads.compactMap { payload in
            guard var summary = try? decoder.decode(ArtistLibraryPayloadSummary.self, from: payload) else { return nil }
            if let raw = summary.dateAddedRaw {
                summary.dateAdded = withoutFraction.date(from: raw) ?? withFraction.date(from: raw)
            }
            return summary
        }
    }
}
