import Foundation
import SwiftData

extension Notification.Name {
    /// Postée quand `CloudSyncEngine` applique un point d'historique de valeur reçu d'un autre
    /// appareil, pour que `StatsViewModel` recharge `valueHistoryPoints` s'il est déjà ouvert.
    static let collectionSnapshotsChanged = Notification.Name("com.spinlog.collectionSnapshotsChanged")
}

/// Formate une date en clé de jour stable (fuseau local), utilisée comme identifiant unique pour
/// garantir au plus un point d'historique par jour, quel que soit le modèle.
private nonisolated func dayStamp(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = .current
    return formatter.string(from: date)
}

/// Point de mesure temporel léger de la valeur globale de la collection (`GET
/// /users/{username}/collection/value`). Conforme aux CGU Discogs : aucune métadonnée de disque
/// (titre, artiste, image...) n'est stockée, seulement des montants et une date.
@Model
final class CollectionSnapshot {
    @Attribute(.unique) var id: String
    var date: Date
    var currency: String
    var low: Double
    var median: Double
    var high: Double

    init(date: Date = Date(), currency: String, low: Double, median: Double, high: Double) {
        self.id = dayStamp(for: date)
        self.date = date
        self.currency = currency
        self.low = low
        self.median = median
        self.high = high
    }
}

/// Point de mesure temporel léger du prix estimé d'une release précise (issu des suggestions de
/// prix Discogs), identifié uniquement par son `releaseId` — jamais de titre, artiste ou image.
@Model
final class ReleasePriceSnapshot {
    @Attribute(.unique) var id: String
    var releaseId: Int
    var date: Date
    var currency: String
    var medianPrice: Double
    /// État déclaré utilisé pour ce calcul (ex. "Near Mint (NM or M-)"), pour pouvoir invalider le
    /// cache si l'utilisateur change l'état renseigné sur son exemplaire avant les 24h.
    var condition: String?

    init(releaseId: Int, date: Date = Date(), currency: String, medianPrice: Double, condition: String?) {
        self.releaseId = releaseId
        self.date = date
        self.currency = currency
        self.medianPrice = medianPrice
        self.condition = condition
        self.id = "\(releaseId)_\(dayStamp(for: date))"
    }
}
