import Foundation

/// Information d'un exemplaire que l'utilisateur veut compléter : sert de filtre « Sans … » de la
/// Collection (voir `CollectionDisplayState.missingFields`). La valeur vient de `CopyDetailsStore`.
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

    /// Vrai si l'exemplaire n'a pas cette information.
    @MainActor
    func isMissing(forInstanceId instanceId: Int, in store: CopyDetailsStore = .shared) -> Bool {
        switch self {
        case .purchasePrice: store.purchasePrice(for: instanceId) == nil
        case .mediaCondition: store.mediaCondition(for: instanceId) == nil
        }
    }
}
