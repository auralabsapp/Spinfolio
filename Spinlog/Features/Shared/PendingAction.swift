import Foundation

enum ActionType: String, Codable, Sendable {
    case addToCollection
    case removeFromCollection
    case addToWantlist
    case removeFromWantlist
    case updateCollectionField
    case moveCollectionInstance
    /// Note (étoiles) d'un exemplaire : `value` porte la note, de 0 à 5.
    case updateCollectionRating
}

nonisolated struct PendingAction: Identifiable, Codable, Sendable {
    let id: UUID
    let type: ActionType
    let releaseId: Int
    /// Dossier courant de l'exemplaire au moment de l'action (utilisé dans le chemin de la
    /// requête Discogs). Pour `.moveCollectionInstance`, c'est le dossier de départ.
    let folderId: Int?
    let instanceId: Int?
    let date: Date
    var retryCount: Int
    /// Identifiant du champ personnalisé Discogs modifié (seulement pour `.updateCollectionField`).
    let fieldId: Int?
    /// Nouvelle valeur du champ personnalisé (seulement pour `.updateCollectionField`).
    let value: String?
    /// Dossier de destination (seulement pour `.moveCollectionInstance`).
    let targetFolderId: Int?
    /// Compte Discogs auquel appartient l'action, renseigné par `OfflineSyncQueue.enqueue` : une
    /// action ne doit jamais être rejouée avec les identifiants d'un autre compte. `nil` pour les
    /// actions persistées par une version antérieure (rejouées sur le compte connecté, comme avant).
    var username: String?
    /// Exemplaires déjà rattachés à un autre ajout du même disque (seulement pour
    /// `.addToCollection`) : ils ne doivent pas être pris pour la trace de cet ajout-ci (voir
    /// `OfflineSyncQueue.matchingAlreadyAddedInstance`). `nil` pour les actions plus anciennes.
    var excludedInstanceIds: [Int]?

    /// Indique si l'action peut être rejouée pour le compte `username`.
    func belongs(to username: String) -> Bool {
        guard let owner = self.username else { return true }
        return owner.caseInsensitiveCompare(username) == .orderedSame
    }

    init(
        id: UUID = UUID(),
        type: ActionType,
        releaseId: Int,
        folderId: Int? = nil,
        instanceId: Int? = nil,
        date: Date = Date(),
        retryCount: Int = 0,
        fieldId: Int? = nil,
        value: String? = nil,
        targetFolderId: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.releaseId = releaseId
        self.folderId = folderId
        self.instanceId = instanceId
        self.date = date
        self.retryCount = retryCount
        self.fieldId = fieldId
        self.value = value
        self.targetFolderId = targetFolderId
    }
}

enum OfflineSyncError: LocalizedError {
    case ambiguousInstance

    var errorDescription: String? {
        switch self {
        case .ambiguousInstance:
            return String(localized: "plusieurs exemplaires de cet album, supprime-le manuellement")
        }
    }
}

extension Notification.Name {
    /// Une action hors ligne a été abandonnée (refus définitif de Discogs ou action trop
    /// ancienne) : `userInfo["type"]` porte le `rawValue` de son `ActionType`.
    static let offlineActionDropped = Notification.Name("com.spinlog.offlineActionDropped")
}
