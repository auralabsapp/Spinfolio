import Foundation

/// État de la configuration du suivi de plus-value pour un compte, lu depuis les préférences
/// (aucun appel réseau) : la page « Comment ça fonctionne ? » l'affiche pour dire à l'utilisateur
/// ce qui manque, plutôt que de seulement l'expliquer.
struct PurchasePriceSetup: Equatable {
    let purchasePriceFieldId: Int?
    let mediaConditionFieldId: Int?
    let currency: String

    /// Sans champ de prix d'achat, aucun exemplaire n'a de prix payé : pas de plus-value possible.
    var hasPriceField: Bool { purchasePriceFieldId != nil }

    /// Sans champ d'état, la cote retombe sur la moyenne de toutes les suggestions : moins précise,
    /// mais le calcul reste possible.
    var hasConditionField: Bool { mediaConditionFieldId != nil }

    var isComplete: Bool { hasPriceField && hasConditionField }

    @MainActor
    static func load(for username: String?) -> PurchasePriceSetup {
        guard let username else {
            return PurchasePriceSetup(purchasePriceFieldId: nil, mediaConditionFieldId: nil, currency: "EUR")
        }
        return PurchasePriceSetup(
            purchasePriceFieldId: CollectionPreferencesStore.purchasePriceFieldId(for: username),
            mediaConditionFieldId: CollectionPreferencesStore.mediaConditionFieldId(for: username),
            currency: CollectionPreferencesStore.defaultCurrency(for: username)
        )
    }
}
