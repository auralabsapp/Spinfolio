import Foundation

/// Résumé du suivi de plus-value pour un compte, lu depuis l'app (aucun appel réseau) : la page
/// « Comment ça fonctionne ? » le montre pour dire où en sont les données plutôt que de seulement
/// l'expliquer.
struct PurchasePriceSetup: Equatable {
    /// Exemplaires dont le prix d'achat est renseigné.
    let pricedCopies: Int
    /// Exemplaires dont l'état du disque est renseigné.
    let gradedCopies: Int
    /// Champs personnalisés Discogs associés dans Réglages (facultatif) : les valeurs saisies y sont
    /// aussi enregistrées.
    let hasPriceField: Bool
    let hasConditionField: Bool
    let currency: String

    /// Quelque chose est renseigné : la plus-value peut se calculer pour au moins un exemplaire.
    var hasData: Bool { pricedCopies > 0 }

    /// Sans aucun champ associé, rien n'est envoyé à Discogs.
    var isLinkedToDiscogs: Bool { hasPriceField || hasConditionField }

    @MainActor
    static func load(for username: String?, store: CopyDetailsStore = .shared) -> PurchasePriceSetup {
        guard let username else {
            return PurchasePriceSetup(pricedCopies: 0, gradedCopies: 0, hasPriceField: false, hasConditionField: false, currency: "EUR")
        }
        return PurchasePriceSetup(
            pricedCopies: store.entries.values.filter { $0.purchasePrice != nil }.count,
            gradedCopies: store.entries.values.filter { $0.mediaCondition != nil }.count,
            hasPriceField: CollectionPreferencesStore.purchasePriceFieldId(for: username) != nil,
            hasConditionField: CollectionPreferencesStore.mediaConditionFieldId(for: username) != nil,
            currency: CollectionPreferencesStore.defaultCurrency(for: username)
        )
    }
}
