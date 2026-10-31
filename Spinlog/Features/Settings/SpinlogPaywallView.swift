import SwiftUI
import StoreKit

private let goldWarm = Color.goldWarm

/// Fenêtre d'incitation à Spinlog Premium (Paywall). Écran entièrement à nous : contenu marketing
/// défilant (illustration, avantages) et panneau d'achat épinglé en bas (`PaywallPurchasePanel`).
/// `SubscriptionStoreView` n'est plus utilisé : il imposait ses marges et ses cadres autour des forfaits.
/// Les achats passent par l'action `purchase` de l'environnement StoreKit et `handlePurchase`
/// (validation, fin de transaction, mise à jour des droits). L'essai gratuit de l'annuel n'est annoncé
/// qu'aux personnes qui y sont éligibles.
struct SpinlogPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase
    @State private var purchaseErrorMessage: String? = nil
    @State private var subscriptionManager = SubscriptionManager.shared
    @State private var premiumStore = PremiumStore.shared
    @State private var selectedKind: PaywallPlan.Kind = .yearly
    /// Produit en cours d'achat ; un seul à la fois (tous les boutons d'achat sont alors désactivés).
    @State private var purchasingProductID: String? = nil
    @State private var isRestoring = false
    /// Éligibilité à l'essai gratuit de l'annuel, vérifiée auprès de StoreKit (jamais présumée).
    @State private var isEligibleForTrial = false
    /// Achat à vie fait par une personne encore abonnée : Apple ne résilie pas l'abonnement, l'alerte
    /// l'invite à le faire (et ferme le paywall ensuite).
    @State private var showsSubscriptionCancellationPrompt = false
    /// `Bool` plutôt que `sheet(item:)` : feuille système StoreKit, sans donnée associée à présenter.
    @State private var showingManageSubscriptions = false
    @State private var showingRedeemCode = false

    private var trialText: String? {
        isEligibleForTrial ? subscriptionManager.freeTrialText(for: .yearly) : nil
    }

    /// Prix de l'achat à vie, masqué si StoreKit ne renvoie pas le produit (réseau, pas encore
    /// approuvé) ou si la personne l'a déjà.
    private var lifetimePrice: String? {
        guard let lifetime = subscriptionManager.lifetimeProduct, !subscriptionManager.hasLifetime else { return nil }
        return lifetime.displayPrice
    }

    var body: some View {
        ScrollView {
            PaywallMarketingContent(trialText: trialText)
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PaywallPurchasePanel(
                plans: subscriptionManager.paywallPlans,
                isLoadingPlans: subscriptionManager.isLoading,
                selectedKind: $selectedKind,
                trialText: trialText,
                lifetimePrice: lifetimePrice,
                isPurchasing: purchasingProductID != nil,
                isPurchasingLifetime: purchasingProductID == PremiumProductID.lifetime,
                isRestoring: isRestoring,
                onSubscribe: subscribe,
                onLifetime: purchaseLifetime,
                onRestore: restorePurchases,
                onRedeemCode: { showingRedeemCode = true },
                onRetry: { Task { await subscriptionManager.loadProducts() } }
            )
        }
        .background {
            ZStack {
                Color.appBackground
                // Léger voile or qui se fond dans le fond de l'app.
                LinearGradient(
                    colors: [Color.goldAccent.opacity(0.22), Color.appBackground],
                    startPoint: .top,
                    endPoint: .center
                )
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .topTrailing) {
            SheetCloseButton(size: 16, style: .prominentOnMedia)
                .padding(.top, 20)
                .padding(.trailing, 30)
        }
        .tint(goldWarm)
        // Toujours recharger à l'ouverture : les prix chargés au lancement peuvent dater d'une autre boutique
        // (voir `SubscriptionManager.startStorefrontListener`) ; les forfaits déjà connus restent affichés
        // pendant la mise à jour.
        .task {
            await subscriptionManager.loadProducts()
        }
        .task(id: subscriptionManager.yearlyProduct?.id) {
            guard let subscription = subscriptionManager.yearlyProduct?.subscription else { return }
            isEligibleForTrial = await subscription.isEligibleForIntroOffer
        }
        // Code d'offre utilisé : le Premium arrive par `Transaction.updates`, le paywall n'a plus lieu d'être.
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
        .offerCodeSheet(isPresented: $showingRedeemCode, message: $purchaseErrorMessage)
        .onChange(of: showingManageSubscriptions) { _, isShown in
            if !isShown && subscriptionManager.hasLifetime { dismiss() }
        }
    }

    // MARK: - Achats

    private func subscribe() {
        let plan: SubscriptionPlanID = selectedKind == .yearly ? .yearly : .monthly
        guard let product = subscriptionManager.product(for: plan) else { return }
        startPurchase(of: product)
    }

    private func purchaseLifetime() {
        guard let product = subscriptionManager.lifetimeProduct else { return }
        startPurchase(of: product)
    }

    private func startPurchase(of product: Product) {
        guard purchasingProductID == nil else { return }
        purchasingProductID = product.id
        Task {
            defer { purchasingProductID = nil }
            do {
                await handlePurchase(of: product, result: .success(try await purchase(product)))
            } catch {
                await handlePurchase(of: product, result: .failure(error))
            }
        }
    }

    /// Restauration manuelle : le message dit si quelque chose a été retrouvé. Un abonnement ou un achat
    /// à vie retrouvé ferme le paywall (voir aussi `onChange(of: premiumStore.hasSubscription)`).
    private func restorePurchases() {
        isRestoring = true
        Task {
            defer { isRestoring = false }
            do {
                try await subscriptionManager.restorePurchases()
            } catch {
                purchaseErrorMessage = AppMessages.restoreFailed
                return
            }
            if premiumStore.isPremium {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } else {
                purchaseErrorMessage = AppMessages.restoreNothingFound
            }
        }
    }

    /// Traitement commun d'un achat (abonnement ou achat à vie). On valide la transaction, on la
    /// termine et on met à jour les droits ici : rien ne garantit qu'elle repasse par
    /// `Transaction.updates`, et le Premium pouvait sinon ne pas s'activer avant le prochain lancement.
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
            // validation différée) : sans ce cas, l'écran restait figé sans aucun retour.
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

/// Même structure que `SpinlogPaywallView` (contenu défilant + panneau épinglé), avec de faux forfaits :
/// permet de juger la hauteur de l'ensemble sans produits StoreKit.
#Preview("Mise en page (faux forfaits)") {
    ScrollView {
        PaywallMarketingContent(trialText: "1 semaine d'essai gratuit")
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 16)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
        PaywallPurchasePanel(
            plans: [
                PaywallPlan(kind: .yearly, id: "y", displayPrice: "17,99 €", monthlyEquivalent: "1,50 €", savingsPercent: 25),
                PaywallPlan(kind: .monthly, id: "m", displayPrice: "1,99 €", monthlyEquivalent: nil, savingsPercent: nil)
            ],
            isLoadingPlans: false,
            selectedKind: .constant(.yearly),
            trialText: "1 semaine d'essai gratuit",
            lifetimePrice: "39,99 €",
            isPurchasing: false,
            isPurchasingLifetime: false,
            isRestoring: false,
            onSubscribe: {}, onLifetime: {}, onRestore: {}, onRedeemCode: {}, onRetry: {}
        )
    }
    .background(Color.appBackground)
}
