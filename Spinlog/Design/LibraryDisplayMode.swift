import Foundation

/// Mode d'affichage de la bibliothèque (Collection ou Wantlist)
enum LibraryDisplayMode: String, CaseIterable, Identifiable, Codable {
    case list = "list"
    case grid = "grid"
    case carousel = "carousel"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return "Liste"
        case .grid: return "Mosaïque"
        case .carousel: return "Carrousel"
        }
    }

    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.3x3.fill"
        case .carousel: return "rectangle.portrait.on.rectangle.portrait"
        }
    }
}

/// Déclencheur pour faire défiler une vue vers un élément spécifique
struct ScrollTargetTrigger: Equatable, Sendable {
    let id: Int
    let token: UUID

    init(id: Int, token: UUID = UUID()) {
        self.id = id
        self.token = token
    }
}
