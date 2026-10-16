import Foundation

/// Une release dans la wantlist d'un utilisateur.
struct WantlistItem: Identifiable, Sendable {
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
    /// `NSCache` (thread-safe nativement) plutôt qu'un dictionnaire simple : `dateAddedDate` est
    /// appelé aussi bien depuis l'affichage des lignes (main actor) que depuis le tri en
    /// arrière-plan. Voir le même cache dans `CollectionItem.dateAddedDate` (régression mesurée
    /// à l'Instruments : 615ms de temps propre pour cette seule ré-analyse ISO8601 répétée).
    private static let dateCache = NSCache<NSString, NSDate>()

    var dateAddedDate: Date? {
        let key = dateAdded as NSString
        if let cached = Self.dateCache.object(forKey: key) {
            return cached as Date
        }
        guard let parsed = Self.isoFormatter.date(from: dateAdded) ?? Self.isoFormatterNoFraction.date(from: dateAdded) else {
            return nil
        }
        Self.dateCache.setObject(parsed as NSDate, forKey: key)
        return parsed
    }

    /// La wantlist n'a pas d'identifiant d'instance séparé : `id` est déjà l'identifiant de release.
    var releaseId: Int { id }
}

/// `init(from:)`/`encode(to:)` explicites et `nonisolated`, plutôt qu'une synthèse automatique
/// de `Codable` : contrairement à l'isolation héritée d'un protocole (où déclarer la conformance
/// dans une extension suffit à devenir `nonisolated`), l'isolation par défaut de la cible
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) continue de s'appliquer à une conformance
/// synthétisée même depuis une extension — seule une méthode explicitement marquée `nonisolated`
/// y échappe. Nécessaire pour que `LocalDataStore` puisse décoder en arrière-plan (`Task.detached`).
extension WantlistItem: Codable {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        rating = try container.decode(Int.self, forKey: .rating)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        dateAdded = try container.decode(String.self, forKey: .dateAdded)
        basicInformation = try container.decode(BasicInformation.self, forKey: .basicInformation)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(rating, forKey: .rating)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(dateAdded, forKey: .dateAdded)
        try container.encode(basicInformation, forKey: .basicInformation)
    }
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
