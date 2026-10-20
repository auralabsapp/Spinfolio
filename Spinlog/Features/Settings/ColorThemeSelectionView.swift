import SwiftUI

/// Écran de sélection du thème de couleur de l'application.
///
/// Permet de choisir parmi 9 ambiances soignées, du rose signature aux tons classiques,
/// naturels, feutrés ou minimalistes.
struct ColorThemeSelectionView: View {
    @State private var themeManager = ThemeManager.shared
    @State private var premiumStore = PremiumStore.shared
    @State private var showingPremiumSheet = false

    var body: some View {
        List {
            // Aperçu dynamique du thème sélectionné
            Section {
                themeLivePreviewCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .listRowBackground(Color.clear)
            }

            // Liste des thèmes disponibles
            Section {
                ForEach(AppColorTheme.allCases) { theme in
                    themeRow(theme)
                        .listRowBackground(Color.clear)
                }
            } header: {
                Text("Palettes disponibles")
            } footer: {
                // Aussi pendant la démo, où tout est débloqué : montre ce que l'abonnement apporte.
                if !premiumStore.isPremium || premiumStore.showsDemoPremiumBadges {
                    Text("Le thème \(AppInfo.name) Signature est inclus pour tous. Les 8 thèmes alternatifs sont débloqués avec le compte Premium.")
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .listRowSeparatorTint(Color.appSeparator)
        .navigationTitle("Couleur du thème")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPremiumSheet) {
            PremiumFeaturesSheet()
        }
    }

    // MARK: - Carte d'aperçu dynamique

    private var themeLivePreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(themeManager.currentTheme.primaryColor)
                        .frame(width: 44, height: 44)
                        .shadow(color: themeManager.currentTheme.primaryColor.opacity(0.35), radius: 6, y: 3)

                    Image(systemName: themeManager.currentTheme.iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(themeManager.currentTheme.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if themeManager.currentTheme.isPremiumOnly {
                            Text("PREMIUM")
                                .font(.emphasisLabel)
                                .foregroundStyle(themeManager.currentTheme.primaryColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(themeManager.currentTheme.badgeColor, in: Capsule())
                        }
                    }

                    Text(themeManager.currentTheme.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondaryText)
                }
            }

            Divider().overlay(Color.appSeparator).opacity(0.2)

            // Démonstrateurs d'éléments d'interface
            VStack(alignment: .leading, spacing: 10) {
                Text("Aperçu des éléments")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appSecondaryText)
                    .textCase(.uppercase)

                HStack(spacing: 8) {
                    // Badge actif
                    HStack(spacing: 4) {
                        Image(systemName: "opticaldisc.fill")
                            .font(.caption2)
                        Text("33 RPM · LP")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.spinlogPink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.spinlogPinkBadge, in: Capsule())

                    // Bouton avec dégradé
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.caption2)
                        Text("En écoute")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.spinlogPinkButtonGradient, in: Capsule())

                    Spacer()

                    // Mini histogramme
                    HStack(alignment: .bottom, spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.spinlogChartDimmedGradient)
                            .frame(width: 5, height: 12)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.spinlogChartGradient)
                            .frame(width: 5, height: 22)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.spinlogChartGradient)
                            .frame(width: 5, height: 17)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.spinlogChartGradient)
                            .frame(width: 5, height: 26)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 8, y: 4)
        )
    }

    // MARK: - Rangée de thème

    @ViewBuilder
    private func themeRow(_ theme: AppColorTheme) -> some View {
        let isSelected = themeManager.currentTheme == theme
        let isLocked = theme.isPremiumOnly && !premiumStore.isPremium

        Button {
            handleThemeTap(theme)
        } label: {
            HStack(spacing: 14) {
                // Pastille de couleur avec dégradé
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [theme.lightColor, theme.primaryColor, theme.deepColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                        .shadow(color: theme.primaryColor.opacity(isSelected ? 0.4 : 0.15), radius: 4, y: 2)

                    Image(systemName: theme.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(theme.displayName)
                            .font(.body.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isLocked ? Color.appSecondaryText : .primary)

                        if theme.isPremiumOnly {
                            Image(systemName: isLocked ? "lock.fill" : "crown.fill")
                                .font(.inlineIcon)
                                .foregroundStyle(isLocked ? Color.appTertiaryText : Color.orange)
                        }
                    }

                    Text(theme.subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(theme.primaryColor)
                } else if isLocked {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appTertiaryText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func handleThemeTap(_ theme: AppColorTheme) {
        if theme.isPremiumOnly && !premiumStore.isPremium {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showingPremiumSheet = true
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            _ = withAnimation(.easeInOut(duration: 0.25)) {
                themeManager.selectTheme(theme, isPremium: premiumStore.isPremium)
            }
        }
    }
}
