import SwiftUI
import StoreKit

private let goldWarm = Color.goldWarm

/// Fenêtre d'incitation à Spinlog Premium (Paywall), basée sur `SubscriptionStoreView` (StoreKit)
/// pour bénéficier des mécanismes natifs d'achat/restauration/mentions légales, avec notre contenu
/// marketing (bannière, liste de fonctionnalités) au-dessus des forfaits, et l'achat à vie en ligne
/// secondaire dessous (`PaywallLifetimeRow`). L'essai gratuit de l'annuel n'est jamais écrit ici :
/// `SubscriptionStoreView` ne l'annonce qu'aux personnes qui y sont éligibles.
struct SpinlogPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase
    @State private var showsAllFeatures: Bool = false
    @State private var purchaseErrorMessage: String? = nil
    @State private var subscriptionManager = SubscriptionManager.shared
    @State private var premiumStore = PremiumStore.shared
    @State private var isPurchasingLifetime = false
    /// Achat à vie fait par une personne encore abonnée : Apple ne résilie pas l'abonnement, l'alerte
    /// l'invite à le faire (et ferme le paywall ensuite).
    @State private var showsSubscriptionCancellationPrompt = false
    /// `Bool` plutôt que `sheet(item:)` : feuille système StoreKit, sans donnée associée à présenter.
    @State private var showingManageSubscriptions = false

    private let termsURL = AppInfo.termsURL
    private let privacyURL = AppInfo.privacyURL

    /// Abonnements proposés, annuel d'abord (l'ordre de la collection fait foi). Identifiants de
    /// produit plutôt que l'identifiant du groupe : l'achat à vie, hors groupe, est géré à part.
    private let subscriptionProductIDs = [SubscriptionPlanID.yearly.rawValue, SubscriptionPlanID.monthly.rawValue]

    var body: some View {
        SubscriptionStoreView(productIDs: subscriptionProductIDs) {
            PaywallMarketingContent(showsAllFeatures: $showsAllFeatures)
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        // Libellé du bouton sur plusieurs lignes : l'offre d'essai et le prix y figurent clairement.
        .subscriptionStoreButtonLabel(.multiline)
        .storeButton(.visible, for: .restorePurchases, .policies, .redeemCode)
        .subscriptionStorePolicyDestination(url: termsURL, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: privacyURL, for: .privacyPolicy)
        .tint(goldWarm)
        .background(Color.appBackground)
        // Fond sur toute la hauteur (placement documenté de `SubscriptionStoreView`) : un léger voile
        // or qui se fond dans le fond de l'app. L'illustration, elle, est dans le contenu marketing.
        .containerBackground(for: .subscriptionStoreFullHeight) {
            LinearGradient(
                colors: [Color.goldAccent.opacity(0.22), Color.appBackground],
                startPoint: .top,
                endPoint: .center
            )
        }
        .onInAppPurchaseCompletion { product, result in
            await handlePurchase(of: product, result: result)
        }
        // Achat à vie : lien discret sous les abonnements, masquée si StoreKit ne renvoie pas le produit
        // (réseau, pas encore approuvé) ou si la personne l'a déjà.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let lifetime = subscriptionManager.lifetimeProduct, !subscriptionManager.hasLifetime {
                PaywallLifetimeRow(displayPrice: lifetime.displayPrice, isPurchasing: isPurchasingLifetime) {
                    purchaseLifetime(lifetime)
                }
                .padding(.horizontal, 22)
                .background(Color.appBackground)
            }
        }
        .task {
            if subscriptionManager.lifetimeProduct == nil { await subscriptionManager.loadProducts() }
        }
        // Code d'offre utilisé depuis le bouton de la boutique : le Premium arrive par
        // `Transaction.updates`, le paywall n'a plus lieu d'être.
        .onChange(of: premiumStore.hasSubscription) { _, isActive in
            if isActive && !showsSubscriptionCancellationPrompt { dismiss() }
        }
        .messageAlert(Text("Information"), message: $purchaseErrorMessage)
        .alert(Text("Premium pour toujours"), isPresented: $showsSubscriptionCancellationPrompt) {
            Button("Gérer mon abonnement") { showingManageSubscriptions = true }
            Button("Plus tard", role: .cancel) { dismiss() }
        } message: {
            Text(AppMessages.lifetimeKeepsSubscription)
        }
        .manageSubscriptionsSheet(isPresented: $showingManageSubscriptions)
        .onChange(of: showingManageSubscriptions) { _, isShown in
            if !isShown && subscriptionManager.hasLifetime { dismiss() }
        }
    }

    // MARK: - Achats

    private func purchaseLifetime(_ product: Product) {
        isPurchasingLifetime = true
        Task {
            defer { isPurchasingLifetime = false }
            do {
                await handlePurchase(of: product, result: .success(try await purchase(product)))
            } catch {
                await handlePurchase(of: product, result: .failure(error))
            }
        }
    }

    /// Traitement commun d'un achat, qu'il vienne de `SubscriptionStoreView` (abonnements) ou de la
    /// ligne d'achat à vie. Ce traitement remplace celui par défaut de StoreKit : rien ne garantit
    /// que la transaction repasse par `Transaction.updates`. On la valide, la termine et met à jour
    /// les droits ici, sinon le Premium pouvait ne pas s'activer avant le prochain lancement (et la
    /// transaction restait non terminée).
    private func handlePurchase(of product: Product, result: Result<Product.PurchaseResult, Error>) async {
        switch result {
        case .success(.success(let verification)):
            do {
                try await subscriptionManager.completePurchase(verification)
            } catch {
                purchaseErrorMessage = AppMessages.purchaseVerificationFailed
                return
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // Apple ne résilie pas l'abonnement en cours quand on achète l'option à vie.
            if product.id == PremiumProductID.lifetime && subscriptionManager.hasActiveSubscription {
                showsSubscriptionCancellationPrompt = true
            } else {
                dismiss()
            }
        case .success(.pending):
            // Achat ni abouti ni annulé (ex: "Demander à acheter" du partage familial, ou
            // validation différée) : sans ce cas, l'écran restait figé sans aucun retour,
            // laissant penser à un blocage plutôt qu'à un achat en attente d'approbation.
            purchaseErrorMessage = String(localized: "Ton achat est en attente de validation (par exemple si \"Demander à acheter\" est activé sur ce compte). Tu seras averti dès qu'il sera approuvé.")
        case .success(.userCancelled):
            break
        case .success:
            break
        case .failure(let error):
            purchaseErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SpinlogPaywallView()
}
