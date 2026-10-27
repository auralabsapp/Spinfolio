import Foundation

/// Champ personnalisé Discogs que l'utilisateur veut compléter : sert de filtre « Sans … » de la
/// Collection (voir `CollectionDisplayState.missingFields`). Le champ lui-même (son identifiant
/// Discogs) est celui choisi pour le compte dans Réglages > Prix d'achat et état.
nonisolated enum LibraryMissingField: String, CaseIterable, Hashable, Sendable {
    case purchasePrice
    case mediaCondition

    var title: LocalizedStringResource {
        switch self {
        case .purchasePrice: "Sans prix d'achat"
        case .mediaCondition: "Sans état du média"
        }
    }

    var systemImage: String {
        switch self {
        case .purchasePrice: "eurosign.circle"
        case .mediaCondition: "sparkles"
        }
    }

    /// Identifiant Discogs du champ choisi pour ce compte, `nil` tant qu'il n'est pas configuré.
    @MainActor
    func fieldId(for username: String) -> Int? {
        switch self {
        case .purchasePrice: CollectionPreferencesStore.purchasePriceFieldId(for: username)
        case .mediaCondition: CollectionPreferencesStore.mediaConditionFieldId(for: username)
        }
    }

    /// Une valeur vide ou faite d'espaces compte pour absente (Discogs renvoie parfois « »).
    static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
