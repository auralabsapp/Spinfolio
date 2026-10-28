import SwiftUI
import StoreKit

// MARK: - Palette Or Hifi / Ambre Collector (partagée, voir Color.goldAccent etc. dans AppTheme.swift)

private let goldAccent = Color.goldAccent
private let goldWarm = Color.goldWarm
private let goldDeep = Color.goldDeep
private let goldLight = Color.goldLight

private var goldHeaderGradient: LinearGradient {
    LinearGradient(
        colors: [
            Color.goldHeaderTop,
            Color.goldHeaderMiddle,
            Color.goldAccent
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

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

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var initialFeaturesCount: Int {
        isIPad ? PremiumFeatureCatalog.all.count : 4
    }

    var body: some View {
        SubscriptionStoreView(productIDs: subscriptionProductIDs) {
            marketingContent
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .storeButton(.visible, for: .restorePurchases, .policies, .redeemCode)
        .subscriptionStorePolicyDestination(url: termsURL, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: privacyURL, for: .privacyPolicy)
        .tint(goldWarm)
        .background(Color.appBackground)
        // Bannière en arrière-plan de l'en-tête : le contenu marketing a des marges, pas le fond
        // (sinon l'illustration n'allait pas bord à bord). Alignée en haut : seule la zone de la
        // bannière est dorée, pas toute la hauteur de l'en-tête.
        .containerBackground(for: .subscriptionStoreHeader, alignment: .top) {
            PaywallHeaderGraphicView()
                .accessibilityHidden(true)
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

    // MARK: - Contenu marketing (bannière + fonctionnalités, affiché au-dessus des forfaits)

    private var marketingContent: some View {
        VStack(spacing: 18) {
            // Réserve la place de la bannière, dessinée en fond d'en-tête (voir `containerBackground`).
            Color.clear.frame(height: PaywallHeaderGraphicView.height)

            VStack(spacing: 6) {
                Text("Obtiens un accès complet")
                    .font(.title.bold())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 6) {
                    Text("Passe à \(AppInfo.name)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appSecondaryText)

                    PremiumPill(style: .prominent)
                }
            }
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 10) {
                let visibleFeatures = (showsAllFeatures || isIPad) ? PremiumFeatureCatalog.all : Array(PremiumFeatureCatalog.all.prefix(initialFeaturesCount))

                VStack(spacing: 0) {
                    ForEach(Array(visibleFeatures.enumerated()), id: \.element.id) { index, feature in
                        featureRow(feature)
                        if index < visibleFeatures.count - 1 {
                            Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 58)
                        }
                    }
                }
                .padding(.vertical, 4)
                .appleMusicGroupedCard()

                if !showsAllFeatures && visibleFeatures.count < PremiumFeatureCatalog.all.count {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showsAllFeatures = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Color.goldText)

                            Text("et \(PremiumFeatureCatalog.all.count - visibleFeatures.count) fonctionnalités supplémentaires")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.goldText)
                        }
                        .padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 6)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Ligne de fonctionnalité

    private func featureRow(_ feature: PremiumFeatureInfo) -> some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsIcon(systemName: feature.icon, backgroundColor: feature.paywallColor ?? feature.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(feature.description)
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Illustration graphique du Header en tons Or Hifi / Ambre Collector

private struct PaywallHeaderGraphicView: View {
    static let height: CGFloat = 205

    var body: some View {
        ZStack {
            goldHeaderGradient

            // Composition de supports audio physiques (vinyle, CD, cassette) en harmonie dorée
            ZStack {
                vinylDiscView(labelColor: goldLight, size: 112)
                    .shadow(color: Color.black.opacity(0.4), radius: 8, y: 5)
                    .rotationEffect(.degrees(-8))
                    .offset(x: -90, y: -15)

                cdDiscView(size: 98)
                    .shadow(color: Color.black.opacity(0.35), radius: 8, y: 5)
                    .rotationEffect(.degrees(14))
                    .offset(x: 100, y: -25)

                vinylDiscView(labelColor: goldDeep.opacity(0.9), size: 88)
                    .shadow(color: Color.black.opacity(0.45), radius: 8, y: 6)
                    .rotationEffect(.degrees(11))
                    .offset(x: 115, y: 45)

                cassetteView(width: 130)
                    .shadow(color: Color.black.opacity(0.4), radius: 8, y: 6)
                    .rotationEffect(.degrees(-5))
                    .offset(x: -20, y: 45)
            }

            // Fondu vers l'arrière-plan de la page pour une transition sans couture
            VStack {
                Spacer()
                LinearGradient(
                    colors: [Color.clear, Color.appBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 60)
            }
        }
        .frame(height: Self.height)
        .clipShape(PaywallHeaderCurve())
    }

    private func vinylDiscView(labelColor: Color, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.07), Color(white: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)

            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                .frame(width: size * 0.84, height: size * 0.84)
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
                .frame(width: size * 0.70, height: size * 0.70)
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                .frame(width: size * 0.56, height: size * 0.56)

            AngularGradient(
                colors: [Color.clear, Color.white.opacity(0.12), Color.clear, Color.white.opacity(0.12), Color.clear],
                center: .center
            )
            .clipShape(Circle())
            .frame(width: size, height: size)

            Circle()
                .fill(labelColor)
                .frame(width: size * 0.36, height: size * 0.36)

            Circle()
                .fill(Color(red: 0.08, green: 0.08, blue: 0.12))
                .frame(width: size * 0.10, height: size * 0.10)
        }
    }

    /// CD stylisé : surface nacrée avec reflet irisé teinté or/ambre, petit trou central.
    private func cdDiscView(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color.white.opacity(0.92), goldLight.opacity(0.70),
                            Color.white.opacity(0.88), goldAccent.opacity(0.55),
                            Color.white.opacity(0.92)
                        ],
                        center: .center
                    )
                )
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))

            Circle()
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                .frame(width: size * 0.66, height: size * 0.66)

            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: size * 0.40, height: size * 0.40)

            Circle()
                .fill(Color(white: 0.82))
                .frame(width: size * 0.12, height: size * 0.12)
        }
    }

    /// Cassette audio stylisée : boîtier sombre, fenêtre centrale et deux bobines.
    private func cassetteView(width: CGFloat) -> some View {
        let height = width * 0.62
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: width, height: height)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(goldLight.opacity(0.9))
                .frame(width: width * 0.8, height: height * 0.3)
                .offset(y: -height * 0.2)

            HStack(spacing: width * 0.24) {
                cassetteSpoolView(size: height * 0.36)
                cassetteSpoolView(size: height * 0.36)
            }
            .offset(y: height * 0.12)
        }
    }

    private func cassetteSpoolView(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: size, height: size)
            Circle()
                .fill(Color(white: 0.15))
                .frame(width: size * 0.36, height: size * 0.36)
        }
    }
}

// MARK: - Découpe incurvée de l'en-tête

private nonisolated struct PaywallHeaderCurve: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - 24))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.height - 24),
            control: CGPoint(x: rect.width / 2, y: rect.height + 14)
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    SpinlogPaywallView()
}
