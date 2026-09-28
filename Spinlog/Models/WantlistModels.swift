import Foundation

/// Une release dans la wantlist d'un utilisateur.
struct WantlistItem: Decodable, Identifiable, Sendable {
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
}

struct WantlistResponse: Decodable {
    let pagination: Pagination
    let wants: [WantlistItem]
}
