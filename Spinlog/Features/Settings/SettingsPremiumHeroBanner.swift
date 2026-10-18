import SwiftUI

/// Bannière incitative grand format dans les Réglages,
/// reprenant fidèlement le design "Or Hifi / Ambre Collector" de l'application
/// (carte dorée chaleureuse, macaron cadenas, pastille chevron).
struct SettingsPremiumHeroBanner: View {
    var onTap: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Ligne supérieure : Macaron cadenas, Titre, Prix "À partir de", Chevron
                HStack(alignment: .center, spacing: 12) {
                    // Badge circulaire cadenas or satiné
                    ZStack {
                        Circle()
                            .fill(Color.goldButtonGradient)
                            .frame(width: 44, height: 44)
                            .shadow(color: Color.goldWarm.opacity(0.35), radius: 5, y: 2)

                        Image(systemName: "lock.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.goldAccent)

                            Text("Passe à \(AppInfo.name) Premium")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.primary)
                        }

                        // Prix réel de la boutique (devise locale) ; ligne masquée tant que
                        // StoreKit n'a pas répondu (hors ligne) plutôt qu'un tarif inventé.
                        if let lowestMonthlyPrice = SubscriptionManager.shared.lowestMonthlyPriceString {
                            Text("À partir de \(lowestMonthlyPrice) / mois")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.goldText)
                        }
                    }

                    Spacer(minLength: 4)

                    // Pastille chevron ambrée
                    Circle()
                        .fill(Color.goldBadgeBg)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "chevron.right")
                                .font(.inlineIcon)
                                .foregroundStyle(Color.goldWarm)
                        )
                }

                // Ligne inférieure
                Text("Débloque tout le potentiel de ta collection")
                    .font(.subheadline)
                    .foregroundStyle(Color.appSecondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    Color(uiColor: .secondarySystemGroupedBackground)

                    // Halo dégradé or chaleureux
                    LinearGradient(
                        colors: [
                            Color.goldAccent.opacity(0.20),
                            Color.goldWarm.opacity(0.06),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.goldAccent.opacity(0.50),
                                Color.goldWarm.opacity(0.18),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}
