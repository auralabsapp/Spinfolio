import Foundation

// Types des enregistrements CloudKit synchronisés par `CloudSyncEngine` (genres d'enregistrement
// et instantanés JSON des préférences), séparés du moteur lui-même.
/// Identifie, à partir du `recordName` d'un `CKRecord`, à quel store local un enregistrement
/// synchronisé correspond. Chaque genre a son propre `recordType` CloudKit et sa propre
/// convention de nommage, mais partage le même champ `payload` (JSON) et la même zone par compte
/// (`account-<username>`), gérés génériquement par `CloudSyncEngine`.
nonisolated enum SyncedRecordKind: Equatable {
    /// Un exemplaire de la collection et ses tags (voir `TagStore`).
    case tag(instanceId: Int)
    /// Une session d'écoute individuelle (voir `ListeningLogStore`) : contrairement aux autres
    /// genres, chaque session est son propre `CKRecord` et peut être supprimée individuellement.
    case listeningSession(id: UUID)
    /// Préférences "durables" de la collection (voir `CollectionPreferencesStore`) : un seul
    /// enregistrement singleton par compte.
    case collectionPreferences
    /// Personnalisations de tri des artistes (voir `ShelfPreferencesStore`) : un seul
    /// enregistrement singleton par compte.
    case shelfPreferences
    /// Point d'historique de la valeur globale de la collection pour un jour donné (voir
    /// `CollectionSnapshot`/`LocalDataStore`) : un enregistrement par jour, jamais supprimé.
    case collectionSnapshot(dayStamp: String)
    /// Une alerte de prix wantlist (voir `WantlistAlertStore`) : un enregistrement par release,
    /// qui peut être supprimé individuellement (comme les sessions d'écoute).
    case wantlistAlert(releaseId: Int)
    /// La bibliothèque de tags "autonomes" (créés sans être encore appliqués à un exemplaire —
    /// voir `TagStore.standaloneTags`) : un seul enregistrement singleton par compte.
    case standaloneTags
    /// Sections (Albums, Singles & EP…) des masters Discogs déjà classés (voir
    /// `DiscogsWorkCategoryCache`) : un seul enregistrement singleton par compte. Partagé pour
    /// qu'un classement fait sur un appareil (une requête par master) serve aux autres.
    case discogsWorkCategories
    /// Thème de couleur (`ThemeManager`), apparence clair/sombre/système et durée maximale de la
    /// Live Activity d'écoute (`AppearancePreferencesStore`) : un seul enregistrement singleton
    /// par compte. Contrairement à la connexion Apple Music (device-wide, jamais synchronisée et
    /// réinitialisée à la déconnexion — voir `DiscogsAuthManager.logout()`), ces réglages sont
    /// propres au compte Discogs et doivent se retrouver à la reconnexion ou sur un autre appareil.
    case appPreferences
    /// Grades franchis et leur date (voir `GradeStore`) : un seul enregistrement singleton par
    /// compte, toujours fusionné (jamais remplacé) puisqu'un grade ne se perd pas.
    case grades

    private static let tagPrefix = "tags_"
    private static let sessionPrefix = "session_"
    private static let collectionPreferencesRecordName = "preferences"
    private static let shelfPreferencesRecordName = "shelfOverrides"
    private static let snapshotPrefix = "snapshot_"
    private static let wantlistAlertPrefix = "alert_"
    private static let standaloneTagsRecordName = "standaloneTags"
    private static let discogsWorkCategoriesRecordName = "discogsWorkCategories"
    private static let appPreferencesRecordName = "appPreferences"
    private static let gradesRecordName = "grades"

    /// Toujours fusionné avec la version distante (jamais remplacé) : exclu de la règle « la
    /// modification la plus récente l'emporte » (voir `CloudSyncModificationLog`).
    var isAlwaysMerged: Bool {
        switch self {
        case .discogsWorkCategories, .grades: return true
        default: return false
        }
    }

    var recordName: String {
        switch self {
        case .tag(let instanceId): return "\(Self.tagPrefix)\(instanceId)"
        case .listeningSession(let id): return "\(Self.sessionPrefix)\(id.uuidString)"
        case .collectionPreferences: return Self.collectionPreferencesRecordName
        case .shelfPreferences: return Self.shelfPreferencesRecordName
        case .collectionSnapshot(let dayStamp): return "\(Self.snapshotPrefix)\(dayStamp)"
        case .wantlistAlert(let releaseId): return "\(Self.wantlistAlertPrefix)\(releaseId)"
        case .standaloneTags: return Self.standaloneTagsRecordName
        case .discogsWorkCategories: return Self.discogsWorkCategoriesRecordName
        case .appPreferences: return Self.appPreferencesRecordName
        case .grades: return Self.gradesRecordName
        }
    }

    var recordType: String {
        switch self {
        case .tag: return "TagAssignment"
        case .listeningSession: return "ListeningSession"
        case .collectionPreferences: return "CollectionPreferences"
        case .shelfPreferences: return "ShelfPreferences"
        case .collectionSnapshot: return "CollectionValueSnapshot"
        case .wantlistAlert: return "WantlistAlert"
        case .standaloneTags: return "StandaloneTags"
        case .discogsWorkCategories: return "DiscogsWorkCategories"
        case .appPreferences: return "AppPreferences"
        case .grades: return "Grades"
        }
    }

    static func from(recordName: String) -> SyncedRecordKind? {
        if recordName.hasPrefix(tagPrefix), let instanceId = Int(recordName.dropFirst(tagPrefix.count)) {
            return .tag(instanceId: instanceId)
        }
        if recordName.hasPrefix(sessionPrefix),
           let id = UUID(uuidString: String(recordName.dropFirst(sessionPrefix.count))) {
            return .listeningSession(id: id)
        }
        if recordName == collectionPreferencesRecordName { return .collectionPreferences }
        if recordName == shelfPreferencesRecordName { return .shelfPreferences }
        if recordName.hasPrefix(snapshotPrefix) {
            return .collectionSnapshot(dayStamp: String(recordName.dropFirst(snapshotPrefix.count)))
        }
        if recordName.hasPrefix(wantlistAlertPrefix),
           let releaseId = Int(recordName.dropFirst(wantlistAlertPrefix.count)) {
            return .wantlistAlert(releaseId: releaseId)
        }
        if recordName == standaloneTagsRecordName { return .standaloneTags }
        if recordName == discogsWorkCategoriesRecordName { return .discogsWorkCategories }
        if recordName == appPreferencesRecordName { return .appPreferences }
        if recordName == gradesRecordName { return .grades }
        return nil
    }
}

/// Instantané synchronisable des préférences de collection "durables" (voir
/// `CollectionPreferencesStore`) : uniquement celles qui ont du sens à retrouver identiques sur
/// tous les appareils (devise, champs de suivi de cote, dossier d'ajout par défaut) — pas le
/// tri/filtre actif ni le dernier dossier consulté, qui restent volontairement propres à chaque
/// appareil.
struct SyncedCollectionPreferences: Codable, Sendable {
    let defaultCurrency: String
    let purchasePriceFieldId: Int?
    let mediaConditionFieldId: Int?
    let defaultAddFolderId: Int
}

/// Instantané synchronisable des préférences de rangement (voir `ShelfPreferencesStore`) : la
/// règle de tri, les deux réglages "ignorer les articles"/"trier par nom de famille", et les
/// personnalisations manuelles par artiste.
struct SyncedShelfPreferences: Codable, Sendable {
    let sortStrategy: String
    let ignoreArticles: Bool
    let sortByLastName: Bool
    let restrictToSameFolder: Bool
    let customArtistSortOverrides: [String: String]

    private enum CodingKeys: String, CodingKey {
        case sortStrategy, ignoreArticles, sortByLastName, restrictToSameFolder, customArtistSortOverrides
    }

    init(
        sortStrategy: String,
        ignoreArticles: Bool,
        sortByLastName: Bool,
        restrictToSameFolder: Bool,
        customArtistSortOverrides: [String: String]
    ) {
        self.sortStrategy = sortStrategy
        self.ignoreArticles = ignoreArticles
        self.sortByLastName = sortByLastName
        self.restrictToSameFolder = restrictToSameFolder
        self.customArtistSortOverrides = customArtistSortOverrides
    }

    /// `restrictToSameFolder` est absent des payloads écrits par une version antérieure de
    /// l'app sur un autre appareil : `decodeIfPresent` évite de faire échouer tout le décodage
    /// (et donc de perdre les autres préférences déjà synchronisées) pour ce seul champ récent.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sortStrategy = try container.decode(String.self, forKey: .sortStrategy)
        ignoreArticles = try container.decode(Bool.self, forKey: .ignoreArticles)
        sortByLastName = try container.decode(Bool.self, forKey: .sortByLastName)
        restrictToSameFolder = try container.decodeIfPresent(Bool.self, forKey: .restrictToSameFolder) ?? false
        customArtistSortOverrides = try container.decode([String: String].self, forKey: .customArtistSortOverrides)
    }
}

/// Instantané synchronisable du thème de couleur, de l'apparence et de la durée maximale de la
/// Live Activity d'écoute (voir `ThemeManager`/`AppearancePreferencesStore`).
struct SyncedAppPreferences: Codable, Sendable {
    let colorTheme: String
    let appearance: String
    let maxListeningDuration: TimeInterval
}

/// Instantané synchronisable d'un point d'historique de la valeur globale de la collection pour
/// un jour donné (voir `CollectionSnapshot`).
struct SyncedCollectionSnapshot: Codable, Sendable {
    let date: Date
    let currency: String
    let low: Double
    let median: Double
    let high: Double
}
