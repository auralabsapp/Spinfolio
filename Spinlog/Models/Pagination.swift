import Foundation

/// Métadonnées de pagination communes à toutes les listes paginées de l'API Discogs.
struct Pagination: Decodable {
    let page: Int
    let pages: Int
    let perPage: Int
    let items: Int

    private enum CodingKeys: String, CodingKey {
        case page
        case pages
        case perPage = "per_page"
        case items
    }
}
