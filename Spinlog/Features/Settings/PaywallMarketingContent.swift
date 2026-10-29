import SwiftUI
import StoreKit

/// Contenu marketing du paywall (`SpinlogPaywallView`), posé par `SubscriptionStoreView` au-dessus des
/// forfaits : illustration, titre et avantages. Les marges viennent du conteneur de StoreKit ; le
/// fond, lui, est posé par `SpinlogPaywallView` (`containerBackground`).
struct PaywallMarketingContent: View {
    @Binding var showsAllFeatures: Bool
    @State private var subscriptionManager = SubscriptionManager.shared
    /// L'essai n'est annoncé qu'aux personnes qui y sont éligibles (vérifié auprès de StoreKit).
    @State private var isEligibleForTrial = false

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var visibleFeatures: [PremiumFeatureInfo] {
        let all = PremiumFeatureCatalog.all
        return (showsAllFeatures || isIPad) ? all : Array(all.prefix(3))
    }

    var body: some View {
        VStack(spacing: 14) {
            PaywallHeroArtwork()

            VStack(spacing: 6) {
                Text("Obtiens un accès complet")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text("Passe à \(AppInfo.name)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appSecondaryText)
                    PremiumPill(style: .prominent)
                }

                offerHighlights
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(visibleFeatures) { feature in
                    featureRow(feature)
                }

                if visibleFeatures.count < PremiumFeatureCatalog.all.count {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showsAllFeatures = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.footnote.weight(.bold))
                            Text("et \(PremiumFeatureCatalog.all.count - visibleFeatures.count) fonctionnalités supplémentaires")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(Color.goldText)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
        }
        .padding(.bottom, 4)
        .task(id: subscriptionManager.yearlyProduct?.id) {
            guard let subscription = subscriptionManager.yearlyProduct?.subscription else { return }
            isEligibleForTrial = await subscription.isEligibleForIntroOffer
        }
    }

    /// Ce que les forfaits ne disent pas d'eux-mêmes : l'essai gratuit de l'annuel et l'économie
    /// face au mensuel. Visibles sans défiler, au-dessus du sélecteur.
    @ViewBuilder
    private var offerHighlights: some View {
        let trial = isEligibleForTrial ? subscriptionManager.freeTrialText(for: .yearly) : nil
        let savings = subscriptionManager.yearlySavingsPercent
        if trial != nil || savings != nil {
            VStack(spacing: 2) {
                if let trial {
                    Text(trial)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.goldText)
                }
                if let savings {
                    Text("Économise \(savings) % avec l'abonnement annuel")
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.top, 4)
        }
    }

    /// Une fonctionnalité : pastille d'icône, titre et résumé, sans cadre autour (disposition en liste
    /// ouverte, comme les écrans de présentation d'Apple).
    private func featureRow(_ feature: PremiumFeatureInfo) -> some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsIcon(systemName: feature.icon, backgroundColor: feature.paywallColor ?? feature.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(feature.description)
                    .font(.footnote)
                    .foregroundStyle(Color.appSecondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Illustration du paywall : une carte or aux angles arrondis, avec un vinyle, un CD et une cassette.
/// Décorative (masquée à VoiceOver). Dans le contenu marketing plutôt qu'en fond d'en-tête : le fond
/// de `SubscriptionStoreView` n'affichait pas l'image.
struct PaywallHeroArtwork: View {
    /// Compacte pour que les forfaits et le bouton restent visibles sans faire défiler.
    private static let height: CGFloat = 124
    private static let compositionScale: CGFloat = 0.6

    private let goldAccent = Color.goldAccent
    private let goldDeep = Color.goldDeep
    private let goldLight = Color.goldLight

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.goldHeaderTop, Color.goldHeaderMiddle, Color.goldAccent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

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
            .scaleEffect(Self.compositionScale)
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.goldWarm.opacity(0.35), radius: 18, y: 8)
        .accessibilityHidden(true)
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

#Preview {
    ScrollView {
        PaywallMarketingContent(showsAllFeatures: .constant(false))
            .padding(.horizontal, 20)
    }
    .background(Color.appBackground)
}
