import SwiftUI

/// Carte incitative et valorisante affichée pour les fonctionnalités réservées aux comptes premium
/// (`PremiumStore.shared.isPremium == false`).
///
/// Finition « Or Hifi / Ambre Collector » inspirée des standards Apple (Human Interface Guidelines / Podcasts Subscriptions) :
/// - Fond subtil rehaussé d'un halo dégradé ambré / or chaleureux
/// - Fine bordure dorée translucide avec reflets
/// - Badge circulaire cadenas vibrant en or brossé satiné avec cadenas blanc
/// - Mini étiquette « ✨ PREMIUM » dorée
/// - Pastille chevron ambrée et débranchement systématique vers `SpinlogPaywallView`.
struct PremiumLockedCard: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var showsCTA: Bool = true
    var isInteractive: Bool = true
    var action: (() -> Void)? = nil

    @State private var showingPremiumSheet = false

    var body: some View {
        if isInteractive {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let action {
                    action()
                } else {
                    showingPremiumSheet = true
                }
            } label: {
                cardBody
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showingPremiumSheet) {
                SpinlogPaywallView()
            }
        } else {
            cardBody
        }
    }

    private var cardBody: some View {
        HStack(spacing: 10) {
            // Badge circulaire cadenas or satiné avec halo
            ZStack {
                Circle()
                    .fill(Color.goldButtonGradient)
                    .frame(width: 34, height: 34)
                    .shadow(color: Color.goldWarm.opacity(0.40), radius: 5, y: 2)

                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.goldAccent)

                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    HStack(spacing: 2) {
                        Image(systemName: "sparkles")
                            .font(.inlineIcon)
                        Text("PREMIUM")
                            .font(.emphasisLabel)
                    }
                    .foregroundStyle(Color.goldWarm)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.goldBadgeBg, in: Capsule())
                    .fixedSize(horizontal: true, vertical: true)
                }

                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 4)

            if showsCTA {
                Circle()
                    .fill(Color.goldBadgeBg)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "chevron.right")
                            .font(.inlineIcon)
                            .foregroundStyle(Color.goldWarm)
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            ZStack {
                Color(uiColor: .secondarySystemGroupedBackground)

                // Halo dégradé or doux
                LinearGradient(
                    colors: [
                        Color.goldAccent.opacity(0.14),
                        Color.goldWarm.opacity(0.04),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.goldAccent.opacity(0.45),
                            Color.goldWarm.opacity(0.15),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 3)
    }
}

extension View {
    func premiumFeaturesSheet(isPresented: Binding<Bool>) -> some View {
        fullScreenCover(isPresented: isPresented) {
            SpinlogPaywallView()
        }
    }

    func premiumUpsellAlert(isPresented: Binding<Bool>, feature: String) -> some View {
        alert("Fonctionnalité premium", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(feature) est réservé aux comptes premium. Active le compte premium dans Réglages pour en profiter.")
        }
    }
}
