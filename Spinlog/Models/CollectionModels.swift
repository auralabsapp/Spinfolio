import Foundation

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

    var id: Int { instanceId }

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
        folderId = try container.decode(Int.self, forKey: .folderId)
        rating = try container.decode(Int.self, forKey: .rating)
        dateAdded = try container.decode(String.self, forKey: .dateAdded)
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

    private static let isoFormatter = ISO8601DateFormatter()
    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    /// `NSCache` (thread-safe nativement) plutôt qu'un dictionnaire simple : `dateAddedDate` est
    /// `nonisolated` et appelé aussi bien depuis l'affichage des lignes (main actor) que depuis le
    /// tri en arrière-plan (`CollectionSortOption`). Sans ce cache, Instruments a mesuré 615ms de
    /// temps propre dans ce getter pendant un simple défilement de la Collection — l'intégralité
    /// du coût de ré-analyse ISO8601 de la même chaîne, ligne après ligne, frame après frame.
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

struct CollectionReleasesResponse: Decodable {
    let pagination: Pagination
    let releases: [CollectionItem]
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
