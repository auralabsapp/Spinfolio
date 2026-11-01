import Foundation

/// Ce que l'utilisateur sait d'un exemplaire précis, propre à l'app : prix payé et état du disque.
/// Ces données ne dépendent pas de Discogs (voir `CopyDetailsStore`) : elles se saisissent sans
/// compte ni champ personnalisé, et peuvent ensuite être importées depuis Discogs ou lui être
/// renvoyées.
nonisolated struct CopyDetails: Codable, Equatable, Sendable {
    var purchaseAmount: Double?
    /// Devise du prix, propre à chaque prix : un montant en dollars reste en dollars, sans
    /// conversion à l'enregistrement (la conversion se fait à l'affichage, au taux du jour).
    var purchaseCurrency: String?
    var mediaCondition: RecordGrade?
    /// Dernière modification, pour départager deux appareils à la fusion iCloud. Une valeur reprise
    /// de Discogs porte `.distantPast` : toute saisie réelle la remplace.
    var modifiedAt: Date

    init(
        purchaseAmount: Double? = nil,
        purchaseCurrency: String? = nil,
        mediaCondition: RecordGrade? = nil,
        modifiedAt: Date = .now
    ) {
        self.purchaseAmount = purchaseAmount
        self.purchaseCurrency = purchaseCurrency
        self.mediaCondition = mediaCondition
        self.modifiedAt = modifiedAt
    }

    private enum CodingKeys: String, CodingKey {
        case purchaseAmount, purchaseCurrency, mediaCondition, modifiedAt
    }

    /// Tolérant : un état inconnu (ajouté puis retiré entre deux versions) ne fait pas perdre le prix.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        purchaseAmount = try container.decodeIfPresent(Double.self, forKey: .purchaseAmount)
        purchaseCurrency = try container.decodeIfPresent(String.self, forKey: .purchaseCurrency)
        mediaCondition = (try? container.decodeIfPresent(RecordGrade.self, forKey: .mediaCondition)) ?? nil
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
    }

    /// Prix d'achat complet (montant et devise), `nil` s'il manque l'un des deux.
    var purchasePrice: (amount: Double, currency: String)? {
        guard let purchaseAmount, let purchaseCurrency else { return nil }
        return (purchaseAmount, purchaseCurrency)
    }

    /// Plus rien à retenir pour cet exemplaire.
    var isEmpty: Bool {
        purchaseAmount == nil && mediaCondition == nil
    }
}
