import SwiftUI
import StoreKit

/// Feuille système de saisie d'un code d'offre (abonnements et achat à vie), avec le message de
/// résultat. iOS 27 renvoie la transaction vérifiable (`offerCodeRedemption(options:…)`) ; avant, la
/// variante sans options n'en renvoie aucune : le Premium arrive alors par `Transaction.updates`
/// (écouteur de `SubscriptionManager`), et on se contente de relire les droits.
private struct OfferCodeRedemptionModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var message: String?

    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            content.offerCodeRedemption(options: [], isPresented: $isPresented) { result in
                Task { message = await SubscriptionManager.shared.handleOfferCodeResult(result) }
            }
        } else {
            content.offerCodeRedemption(isPresented: $isPresented) { result in
                Task { message = await SubscriptionManager.shared.handleLegacyOfferCodeResult(result) }
            }
        }
    }
}

extension View {
    /// Voir `OfferCodeRedemptionModifier`. `isPresented` est un `Bool` (feuille système sans donnée
    /// associée à présenter, exception à la règle `sheet(item:)`).
    func offerCodeSheet(isPresented: Binding<Bool>, message: Binding<String?>) -> some View {
        modifier(OfferCodeRedemptionModifier(isPresented: isPresented, message: message))
    }
}
