import Foundation

/// Réponse de `GET /oauth/identity`, confirmant l'utilisateur derrière l'access token courant.
struct Identity: Decodable {
    let id: Int
    let username: String
    let resourceURL: String

    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case resourceURL = "resource_url"
    }
}
