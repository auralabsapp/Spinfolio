import SwiftUI

/// Bannière incitative grand format dans les Réglages,
/// reprenant fidèlement le design "Or Hifi / Ambre Collector" de l'application
/// (carte dorée chaleureuse, macaron cadenas, pastille chevron).
struct SettingsPremiumHeroBanner: View {
    var onTap: () -> Void

    // MARK: - Palette Or Hifi / Ambre Collector
    private static let goldAccent = Color(red: 0.95, green: 0.68, blue: 0.18)
    private static let goldWarm = Color(red: 0.88, green: 0.52, blue: 0.12)
    private static let goldBadgeBg = Color(red: 0.95, green: 0.68, blue: 0.18).opacity(0.18)

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
                            .fill(goldButtonGradient)
                            .frame(width: 44, height: 44)
                            .shadow(color: Self.goldWarm.opacity(0.35), radius: 5, y: 2)

                        Image(systemName: "lock.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Self.goldAccent)

                            Text("Passe à \(AppInfo.name) Premium")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.primary)
                        }

                        Text("À partir de 2,50 € / mois")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Self.goldWarm)
                    }

                    Spacer(minLength: 4)

                    // Pastille chevron ambrée
                    Circle()
                        .fill(Self.goldBadgeBg)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Self.goldWarm)
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
                            Self.goldAccent.opacity(0.20),
                            Self.goldWarm.opacity(0.06),
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
                                Self.goldAccent.opacity(0.50),
                                Self.goldWarm.opacity(0.18),
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
