import Foundation

// Lignes des classements et répartitions affichés par l'onglet Stats (voir `StatsViewModel`).
/// Une release de la collection classée par nombre d'écoutes enregistrées.
struct TopAlbumEntry: Identifiable {
    let item: CollectionItem
    let playCount: Int
    var id: Int { item.releaseId }
}

/// Un artiste classé par nombre total d'écoutes cumulées sur tous ses disques possédés.
/// Entrée de la répartition par genre musical.
struct GenreDistributionEntry: Identifiable, Equatable {
    let name: String
    let count: Int
    let percentage: Double
    var id: String { name }
}

/// Détail par style musical au sein d'un genre sélectionné (affiché au tap d'une part du
/// camembert des genres). Pas de pourcentage : un disque a souvent plusieurs styles à la fois,
/// donc ce classement ne se totalise pas à 100 % comme le camembert des genres.
struct StyleBreakdownEntry: Identifiable, Equatable {
    let name: String
    let count: Int
    var id: String { name }
}

/// Entrée de la répartition par label (maison de disques).
struct LabelDistributionEntry: Identifiable, Equatable {
    let name: String
    let count: Int
    let percentage: Double
    var id: String { name }
}

/// Entrée de la répartition par support physique (Vinyles/CD/Cassettes/Autres).
struct MediaFormatDistributionEntry: Identifiable, Equatable {
    let name: String
    let count: Int
    let percentage: Double
    var id: String { name }
}

/// Détail par taille au sein de la part "Vinyles" (12"/10"/7"), affiché au tap de cette part.
struct VinylSizeBreakdownEntry: Identifiable, Equatable {
    let category: ShelfMediaCategory
    let count: Int
    var id: String { category.rawValue }
    var label: String { category.shortSizeLabel }
}

struct TopArtistEntry: Identifiable {
    let name: String
    let totalPlays: Int
    let releaseCount: Int
    /// Artistes Discogs derrière `name` (plusieurs pour un disque en collaboration), pour ouvrir
    /// leur fiche depuis le classement.
    let artists: [ReleaseArtist]
    var id: String { name }
}
