import Foundation
import StoreKit

/// Un forfait d'abonnement tel que le paywall l'affiche. Modèle simple, sans StoreKit à l'exécution :
/// le paywall et ses aperçus ne dépendent ainsi que de données déjà formatées (prix aux réglages du
/// système, voir CLAUDE.md §6), et les textes légaux se testent sans boutique.
struct PaywallPlan: Identifiable, Equatable {
    enum Kind: Equatable {
        case yearly
        case monthly
    }

    let kind: Kind
    /// Identifiant du produit StoreKit.
    let id: String
    let displayPrice: String
    /// Annuel seulement : prix annuel ÷ 12.
    let monthlyEquivalent: String?
    /// Annuel seulement : économie face à douze mensualités, en pourcentage entier.
    let savingsPercent: Int?
}

extension SubscriptionManager {
    /// Forfaits proposés, annuel d'abord ; vide tant que StoreKit n'a rien renvoyé (réseau, produits
    /// non servis pour la boutique) : le paywall affiche alors un état « indisponible ».
    var paywallPlans: [PaywallPlan] {
        var plans: [PaywallPlan] = []
        if let yearly = yearlyProduct {
            plans.append(PaywallPlan(
                kind: .yearly,
                id: yearly.id,
                displayPrice: yearly.displayPrice,
                monthlyEquivalent: yearlyMonthlyEquivalentString,
                savingsPercent: yearlySavingsPercent
            ))
        }
        if let monthly = monthlyProduct {
            plans.append(PaywallPlan(
                kind: .monthly,
                id: monthly.id,
                displayPrice: monthly.displayPrice,
                monthlyEquivalent: nil,
                savingsPercent: nil
            ))
        }
        return plans
    }
}

/// Mentions de renouvellement affichées sous le bouton d'abonnement : exigées par l'App Review (3.1.2)
/// avant tout achat (prix, périodicité, renouvellement automatique, essai le cas échéant).
enum PaywallLegalText {
    /// - Parameters:
    ///   - price: prix du forfait, déjà formaté.
    ///   - trial: texte d'essai gratuit (ex. « 1 semaine d'essai gratuit »), seulement si la personne y est
    ///     éligible et que le forfait en a un.
    nonisolated static func renewal(kind: PaywallPlan.Kind, price: String, trial: String?) -> String {
        switch kind {
        case .yearly:
            if let trial {
                return String(localized: "\(trial), puis \(price) par an. Renouvelé automatiquement jusqu'à ce que tu l'annules.")
            }
            return String(localized: "Renouvelé automatiquement à \(price) par an jusqu'à ce que tu l'annules.")
        case .monthly:
            return String(localized: "Renouvelé automatiquement à \(price) par mois jusqu'à ce que tu l'annules.")
        }
    }
}
