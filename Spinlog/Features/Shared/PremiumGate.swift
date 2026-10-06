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

    // MARK: - Palette Or Hifi / Ambre Collector
    private static let goldAccent = Color(red: 0.95, green: 0.68, blue: 0.18)
    private static let goldWarm = Color(red: 0.88, green: 0.52, blue: 0.12)
    private static let goldBadgeBg = Color(red: 0.95, green: 0.68, blue: 0.18).opacity(0.16)

    private var goldButtonGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.78, blue: 0.28),
                Color(red: 0.88, green: 0.52, blue: 0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

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
                    .fill(goldButtonGradient)
                    .frame(width: 34, height: 34)
                    .shadow(color: Self.goldWarm.opacity(0.40), radius: 5, y: 2)

                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Self.goldAccent)

                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    HStack(spacing: 2) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 7, weight: .black))
                        Text("PREMIUM")
                            .font(.system(size: 8, weight: .heavy))
                    }
                    .foregroundStyle(Self.goldWarm)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Self.goldBadgeBg, in: Capsule())
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
                    .fill(Self.goldBadgeBg)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Self.goldWarm)
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
                        Self.goldAccent.opacity(0.14),
                        Self.goldWarm.opacity(0.04),
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
                            Self.goldAccent.opacity(0.45),
                            Self.goldWarm.opacity(0.15),
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
