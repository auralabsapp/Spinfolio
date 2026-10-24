import AppIntents
import Foundation

/// Un disque de la collection, tel que Siri, Spotlight et l'app Raccourcis le présentent.
/// Construit depuis le cache local (`LocalDataStore`) : disponible hors ligne et sans requête
/// Discogs, au prix de ne connaître que les disques déjà chargés au moins une fois dans l'app.
nonisolated struct RecordEntity: AppEntity, Identifiable, Hashable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Disque"
    static let defaultQuery = RecordEntityQuery()

    /// Identifiant de release Discogs (plusieurs exemplaires d'un même disque n'en font qu'un).
    let id: Int
    let title: String
    let artist: String
    let coverURL: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(artist)")
    }
}

/// Recherche d'un disque par son titre ou son artiste, parmi ceux de la collection en cache.
nonisolated struct RecordEntityQuery: EntityStringQuery {
    func entities(for identifiers: [Int]) async throws -> [RecordEntity] {
        let wanted = Set(identifiers)
        return try await RecordLibrary.records().filter { wanted.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [RecordEntity] {
        RecordLibrary.matching(string, in: try await RecordLibrary.records())
    }

    /// Proposés quand Siri demande « Quel disque ? » : les derniers disques écoutés sur platine.
    func suggestedEntities() async throws -> [RecordEntity] {
        try await RecordLibrary.recentlyListened(limit: 10)
    }
}

/// Erreurs expliquées à l'utilisateur par Siri ou Raccourcis.
nonisolated enum RecordIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notSignedIn
    case emptyLibrary
    case notInCollection

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSignedIn:
            "Connecte-toi à ton compte Discogs dans \(AppInfo.name) pour utiliser ce raccourci."
        case .emptyLibrary:
            "Aucun disque disponible : ouvre ta collection dans \(AppInfo.name) une première fois."
        case .notInCollection:
            "Ce disque n'est pas dans ta collection : une écoute sur platine ne se démarre que pour un disque que tu possèdes."
        }
    }
}
