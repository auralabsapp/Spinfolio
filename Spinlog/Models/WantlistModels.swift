import Foundation

/// Une release dans la wantlist d'un utilisateur.
struct WantlistItem: Codable, Identifiable, Sendable {
    let id: Int
    let rating: Int
    let notes: String?
    let dateAdded: String
    let basicInformation: BasicInformation

    private enum CodingKeys: String, CodingKey {
        case id, rating, notes
        case dateAdded = "date_added"
        case basicInformation = "basic_information"
    }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    var dateAddedDate: Date? {
        Self.isoFormatter.date(from: dateAdded) ?? Self.isoFormatterNoFraction.date(from: dateAdded)
    }

    /// La wantlist n'a pas d'identifiant d'instance séparé : `id` est déjà l'identifiant de release.
    var releaseId: Int { id }
}

/// Permet à `WantlistItem` de réutiliser exactement les mêmes options et logique de tri
/// que `CollectionItem` (voir `CollectionSortOption.swift`) — même construction d'écran
/// pour Collection et Wantlist.
extension WantlistItem: SortableLibraryItem {
    /// `nonisolated` + `assumeIsolated` : exigé par le protocole `SortableLibraryItem` (voir
    /// `CollectionSortOption.swift`) ; `WantlistViewModel` l'appelle toujours depuis l'acteur
    /// principal, donc l'hypothèse d'isolation est toujours vraie ici.
    nonisolated var libraryItemTags: [String] {
        MainActor.assumeIsolated {
            TagStore.shared.tags(for: id, releaseId: releaseId)
        }
    }
}

struct WantlistResponse: Decodable {
    let pagination: Pagination
    let wants: [WantlistItem]
}
