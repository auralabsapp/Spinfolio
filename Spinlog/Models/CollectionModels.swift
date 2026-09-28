import Foundation

/// Un dossier de la collection d'un utilisateur (ex: "All", "Vinyle", ...).
struct CollectionFolder: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let count: Int
    let resourceURL: String

    private enum CodingKeys: String, CodingKey {
        case id, name, count
        case resourceURL = "resource_url"
    }
}

struct CollectionFoldersResponse: Decodable {
    let folders: [CollectionFolder]
}

/// Une release dans la collection d'un utilisateur.
struct CollectionItem: Decodable, Identifiable, Sendable {
    let instanceId: Int
    let id: Int
    let folderId: Int
    let rating: Int
    let dateAdded: String
    let basicInformation: BasicInformation

    var id_: Int { id }

    private enum CodingKeys: String, CodingKey {
        case instanceId = "instance_id"
        case id, rating
        case folderId = "folder_id"
        case dateAdded = "date_added"
        case basicInformation = "basic_information"
    }
}

extension CollectionItem {
    /// Identifiable utilise `instanceId` : deux exemplaires du même vinyle peuvent coexister
    /// dans un même dossier (chacun avec son propre instance).
    var identityId: Int { instanceId }
}

struct CollectionReleasesResponse: Decodable {
    let pagination: Pagination
    let releases: [CollectionItem]
}
