import Foundation

/// Métadonnées de pagination communes à toutes les listes paginées de l'API Discogs.
/// `nonisolated` : décodée hors du fil principal avec les pages de collection et de wantlist.
nonisolated struct Pagination: Decodable, Sendable {
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
