import Foundation
import OSLog

nonisolated private let collectionDecodingLogger = Logger(subsystem: AppInfo.logSubsystem, category: "CollectionDecoding")

/// Un dossier de la collection d'un utilisateur (ex: "All", "Vinyle", ...).
struct CollectionFolder: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let count: Int
    let resourceURL: String

    init(id: Int, name: String, count: Int, resourceURL: String = "") {
        self.id = id
        self.name = name
        self.count = count
        self.resourceURL = resourceURL
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, count
        case resourceURL = "resource_url"
    }
}

struct CollectionFoldersResponse: Decodable {
    let folders: [CollectionFolder]
}

/// Réponse renvoyée par Discogs lors de l'ajout d'une release à un dossier de collection.
struct AddToCollectionResponse: Codable, Sendable {
    let instanceId: Int
    let resourceURL: String

    init(instanceId: Int, resourceURL: String = "") {
        self.instanceId = instanceId
        self.resourceURL = resourceURL
    }

    private enum CodingKeys: String, CodingKey {
        case instanceId = "instance_id"
        case resourceURL = "resource_url"
    }
}

/// Une release dans la collection d'un utilisateur.
/// `Identifiable` s'appuie sur `instanceId` (pas l'id de la release) : deux exemplaires
/// du même vinyle peuvent coexister dans un même dossier, chacun avec sa propre instance.
struct CollectionItem: Codable, Identifiable, Sendable {
    var releaseId: Int
    let folderId: Int
    var rating: Int
    let dateAdded: String
    let basicInformation: BasicInformation
    let instanceId: Int
    var notes: [CollectionFieldValue]

    /// `nonisolated` : exigence de `SortableLibraryItem`, lue pendant le tri en arrière-plan.
    nonisolated var id: Int { instanceId }

    private enum CodingKeys: String, CodingKey {
        case releaseId = "id"
        case folderId = "folder_id"
        case rating
        case dateAdded = "date_added"
        case basicInformation = "basic_information"
        case instanceId = "instance_id"
        case notes
    }

    init(
        releaseId: Int,
        folderId: Int,
        rating: Int,
        dateAdded: String,
        basicInformation: BasicInformation,
        instanceId: Int,
        notes: [CollectionFieldValue] = []
    ) {
        self.releaseId = releaseId
        self.folderId = folderId
        self.rating = rating
        self.dateAdded = dateAdded
        self.basicInformation = basicInformation
        self.instanceId = instanceId
        self.notes = notes
    }

    // `nonisolated` : pur (dé)codage sur `self`/les paramètres, sans aucun état partagé — sans ça,
    // l'isolation par défaut de la cible (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) rend la
    // conformance `Decodable` inutilisable depuis un contexte réellement hors acteur (ex:
    // `LocalDataStore`'s `Task.detached`, qui décode en arrière-plan).
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        releaseId = try container.decode(Int.self, forKey: .releaseId)
        // Champs secondaires tolérants : leur absence ne doit pas faire perdre l'exemplaire.
        folderId = try container.decodeIfPresent(Int.self, forKey: .folderId) ?? DiscogsConstants.allFolderId
        rating = try container.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        dateAdded = try container.decodeIfPresent(String.self, forKey: .dateAdded) ?? ""
        basicInformation = try container.decode(BasicInformation.self, forKey: .basicInformation)
        instanceId = try container.decode(Int.self, forKey: .instanceId)
        notes = try container.decodeIfPresent([CollectionFieldValue].self, forKey: .notes) ?? []
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(releaseId, forKey: .releaseId)
        try container.encode(folderId, forKey: .folderId)
        try container.encode(rating, forKey: .rating)
        try container.encode(dateAdded, forKey: .dateAdded)
        try container.encode(basicInformation, forKey: .basicInformation)
        try container.encode(instanceId, forKey: .instanceId)
        try container.encode(notes, forKey: .notes)
    }

    /// `nonisolated` : appelé aussi bien depuis l'affichage des lignes (main actor) que depuis le
    /// tri en arrière-plan (`CollectionSortOption`). Voir `DiscogsDateParsing` pour le cache
    /// mémoïsé partagé avec `WantlistItem`.
    nonisolated var dateAddedDate: Date? {
        DiscogsDateParsing.dateAdded(from: dateAdded)
    }

    func value(forFieldId fieldId: Int) -> String {
        notes.first { $0.fieldId == fieldId }?.value ?? ""
    }
}

/// Valeur d'un champ personnalisé Discogs pour une instance de release
/// (ex: état de la pochette, notes libres, champs créés par l'utilisateur).
/// L'API renvoie `value` tantôt en string, tantôt en nombre/booléen selon le type de champ :
/// on normalise systématiquement vers une `String`.
struct CollectionFieldValue: Codable, Sendable {
    let fieldId: Int
    let value: String

    private enum CodingKeys: String, CodingKey {
        case fieldId = "field_id"
        case value
    }

    init(fieldId: Int, value: String) {
        self.fieldId = fieldId
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fieldId = try container.decode(Int.self, forKey: .fieldId)
        if let stringValue = try? container.decode(String.self, forKey: .value) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self, forKey: .value) {
            value = boolValue ? "1" : "0"
        } else if let intValue = try? container.decode(Int.self, forKey: .value) {
            value = String(intValue)
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fieldId, forKey: .fieldId)
        try container.encode(value, forKey: .value)
    }
}

/// `nonisolated` : une page (jusqu'à 100 exemplaires) est décodée hors du fil principal, voir
/// `DiscogsAPIClient.collectionItems`.
///
/// Un exemplaire illisible est ignoré (et compté dans les logs) plutôt que de faire échouer toute
/// la page : sinon un seul enregistrement atypique vidait l'onglet Collection avec une erreur de
/// décodage, alors que les autres exemplaires étaient parfaitement valides.
nonisolated struct CollectionReleasesResponse: Decodable, Sendable {
    let pagination: Pagination
    let releases: [CollectionItem]

    private enum CodingKeys: String, CodingKey {
        case pagination, releases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pagination = try container.decode(Pagination.self, forKey: .pagination)
        let lossy = try container.decodeIfPresent(LossyArray<CollectionItem>.self, forKey: .releases)
        releases = lossy?.elements ?? []
        if let dropped = lossy?.droppedCount, dropped > 0 {
            collectionDecodingLogger.error("Page de collection : \(dropped, privacy: .public) exemplaire(s) illisible(s) ignoré(s).")
        }
    }
}

/// Définition d'un champ personnalisé de collection, tel que créé par l'utilisateur
/// dans ses réglages Discogs (ex: "État de la pochette", "Notes").
struct CollectionField: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let type: String
    let options: [String]?

    var isDropdown: Bool { type == "dropdown" }
    var isTextArea: Bool { type == "textarea" }
    var isCheckbox: Bool { type == "checkbox" }
}

struct CollectionFieldsResponse: Decodable {
    let fields: [CollectionField]
}
