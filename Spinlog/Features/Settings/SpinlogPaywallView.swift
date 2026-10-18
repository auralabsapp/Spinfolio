import SwiftUI
import StoreKit

// MARK: - Palette Or Hifi / Ambre Collector (partagée, voir Color.goldAccent etc. dans AppTheme.swift)

private let goldAccent = Color.goldAccent
private let goldWarm = Color.goldWarm
private let goldDeep = Color.goldDeep
private let goldLight = Color.goldLight
private let goldBadgeBg = Color.goldBadgeBg
private var goldButtonGradient: LinearGradient { Color.goldButtonGradient }

private var goldHeaderGradient: LinearGradient {
    LinearGradient(
        colors: [
            Color(red: 0.65, green: 0.36, blue: 0.07),
            Color(red: 0.85, green: 0.50, blue: 0.12),
            Color(red: 0.95, green: 0.68, blue: 0.18)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

/// Description d'une fonctionnalité premium (icône, couleur, titre, résumé) — même contenu que
/// `PremiumFeaturesSheet`, avec la charte Or Hifi / Ambre Collector.
private struct PaywallFeatureInfo: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    // `LocalizedStringResource` : les libellés sont extraits dans le catalogue et traduits
    // (en `String`, ils s'affichaient toujours en français).
    let title: LocalizedStringResource
    let description: LocalizedStringResource
}

private let paywallFeatures: [PaywallFeatureInfo] = [
    PaywallFeatureInfo(
        icon: "banknote.fill",
        color: .green,
        title: "Suivi de cote",
        description: "Renseigne le prix payé pour chaque album et compare-le à sa cote Discogs en temps réel pour voir si tes albums ont pris de la valeur."
    ),
    PaywallFeatureInfo(
        icon: "icloud.fill",
        color: .cyan,
        title: "Synchronisation iCloud",
        description: "Synchronise tags, journal d'écoute sur platine, préférences et personnalisations de tri entre tous tes appareils connectés au même compte."
    ),
    PaywallFeatureInfo(
        icon: "rectangle.stack.badge.plus",
        color: .blue,
        title: "Scan par lot",
        description: "Scanne plusieurs codes-barres à la suite (brocante, disquaire) et ajoute-les en une fois à ta collection ou ta wantlist."
    ),
    PaywallFeatureInfo(
        icon: "bell.fill",
        color: .orange,
        title: "Alertes de prix sur la wantlist",
        description: "Sois averti quand un disque de ta wantlist apparaît à bon prix sur le marketplace Discogs (vérification à l'ouverture de l'app et occasionnellement en arrière-plan, pas en temps réel)."
    ),
    PaywallFeatureInfo(
        icon: "arrow.down.circle.fill",
        color: .teal,
        title: "Mode hors ligne",
        description: "Télécharge toute ta collection et les pochettes en haute résolution pour fouiner en brocante sans aucun réseau."
    ),
    PaywallFeatureInfo(
        icon: "books.vertical.fill",
        color: .purple,
        title: "Où ranger son album",
        description: "Retrouve instantanément où ranger un album dans ton meuble, avec ses voisins immédiats selon ton tri personnalisé."
    ),
    PaywallFeatureInfo(
        icon: "waveform",
        color: goldWarm,
        title: "Palmarès d'écoute sur platine",
        description: "Découvre tes albums et artistes les plus écoutés sur ta platine, tes podiums du mois et de l'année dans Statistiques. Les lectures Apple Music ne sont pas comptées."
    ),
    PaywallFeatureInfo(
        icon: "paintpalette.fill",
        color: goldAccent,
        title: "Thèmes et palettes de couleurs",
        description: "Personnalise l'ambiance visuelle de l'app selon tes goûts avec 8 palettes exclusives (Bleu Cobalt, Vert Émeraude, Orange Crépuscule, Rouge Rubis, Violet Améthyste, Cuivre & Or...)."
    ),
    PaywallFeatureInfo(
        icon: "square.and.arrow.up.fill",
        color: .mint,
        title: "Export CSV & PDF",
        description: "Exporte toute ta discothèque au format tableur (Excel, Numbers, Sheets) avec métadonnées, notes et tags, ou en PDF avec état et prix d'achat."
    )
]

/// Fenêtre d'incitation à l'abonnement Spinlog Premium (Paywall), basée sur `SubscriptionStoreView`
/// (StoreKit) pour bénéficier des mécanismes natifs d'achat/restauration/mentions légales, avec
/// notre contenu marketing (bannière, liste de fonctionnalités) au-dessus des forfaits.
struct SpinlogPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showsAllFeatures: Bool = false
    @State private var purchaseErrorMessage: String? = nil
    @State private var showingPurchaseErrorAlert: Bool = false

    /// CLUF standard d'Apple : couvre les conditions d'utilisation de l'app en l'absence de
    /// conditions personnalisées renseignées dans App Store Connect.
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private let privacyURL = URL(string: "https://auralabsapp.github.io/Spinfolio/privacy.html")!

    /// Identifiant du groupe d'abonnement (voir `Spinlog.storekit` pour les tests locaux — doit
    /// correspondre au groupe réel créé dans App Store Connect pour fonctionner en sandbox/prod).
    private let subscriptionGroupID = "22419469"

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var initialFeaturesCount: Int {
        isIPad ? paywallFeatures.count : 4
    }

    var body: some View {
        SubscriptionStoreView(groupID: subscriptionGroupID) {
            marketingContent
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .storeButton(.visible, for: .restorePurchases, .policies)
        .subscriptionStorePolicyDestination(url: termsURL, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: privacyURL, for: .privacyPolicy)
        .tint(goldWarm)
        .background(Color.appBackground)
        .onInAppPurchaseCompletion { _, result in
            switch result {
            case .success(.success(let verification)):
                // Ce modificateur remplace le traitement par défaut de l'achat : rien ne garantit
                // que la transaction repasse par `Transaction.updates`. On la valide, la termine et
                // met à jour les droits ici, sinon le Premium pouvait ne pas s'activer avant le
                // prochain lancement (et la transaction restait non terminée).
                guard let transaction = try? SubscriptionManager.verify(verification) else {
                    purchaseErrorMessage = String(localized: "L'achat n'a pas pu être vérifié auprès de l'App Store.")
                    showingPurchaseErrorAlert = true
                    return
                }
                await transaction.finish()
                await SubscriptionManager.shared.updateCustomerProductStatus()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            case .success(.pending):
                // Achat ni abouti ni annulé (ex: "Demander à acheter" du partage familial, ou
                // validation différée) : sans ce cas, l'écran restait figé sans aucun retour,
                // laissant penser à un blocage plutôt qu'à un achat en attente d'approbation.
                purchaseErrorMessage = "Ton achat est en attente de validation (par exemple si \"Demander à acheter\" est activé sur ce compte). Tu seras averti dès qu'il sera approuvé."
                showingPurchaseErrorAlert = true
            case .success(.userCancelled):
                break
            case .success:
                break
            case .failure(let error):
                purchaseErrorMessage = error.localizedDescription
                showingPurchaseErrorAlert = true
            }
        }
        .alert("Information", isPresented: $showingPurchaseErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(purchaseErrorMessage ?? "Une erreur inattendue est survenue lors de la communication avec l'App Store.")
        }
    }

    // MARK: - Contenu marketing (bannière + fonctionnalités, affiché au-dessus des forfaits)

    private var marketingContent: some View {
        VStack(spacing: 18) {
            PaywallHeaderGraphicView()

            VStack(spacing: 6) {
                Text("Obtiens un accès complet")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 6) {
                    Text("Passe à \(AppInfo.name)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appSecondaryText)

                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.inlineIcon)
                        Text("PREMIUM")
                            .font(.emphasisLabel)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(goldButtonGradient, in: Capsule())
                    .shadow(color: goldWarm.opacity(0.35), radius: 4, y: 1)
                }
            }
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 10) {
                let visibleFeatures = (showsAllFeatures || isIPad) ? paywallFeatures : Array(paywallFeatures.prefix(initialFeaturesCount))

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

                if !showsAllFeatures && visibleFeatures.count < paywallFeatures.count {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showsAllFeatures = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.goldText)

                            Text("et \(paywallFeatures.count - visibleFeatures.count) fonctionnalités supplémentaires")
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

    private func featureRow(_ feature: PaywallFeatureInfo) -> some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsIcon(systemName: feature.icon, backgroundColor: feature.color)
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
        .frame(height: 205)
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
