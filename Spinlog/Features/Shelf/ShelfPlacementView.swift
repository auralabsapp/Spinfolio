import SwiftUI

/// Vue guidant l'utilisateur pour ranger physiquement son vinyle dans son meuble,
/// avec une présentation horizontale élégante mettant en scène le disque cible au centre
/// entouré de ses 2 voisins immédiats (gauche et droite).
struct ShelfPlacementView: View {
    let targetRelease: Release
    var customCollection: [Release]? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var preferences = ShelfPreferencesStore.shared
    @State private var premiumStore = PremiumStore.shared
    @State private var authManager = DiscogsAuthManager.shared
    @State private var viewModel = ShelfPlacementViewModel()

    /// Calculés une seule fois à l'ouverture, plutôt qu'à chaque image de rendu comme le ferait
    /// une propriété calculée ordinaire : cette recherche relit et redécode toute la collection
    /// locale puis la trie entièrement (voir `ShelfPlacementService.findNeighborsInLocalStore`) —
    /// un calcul coûteux, répété à chaque accès (`neighbors.previous`, `.next`, `.scope`… une
    /// dizaine de fois par rendu), qui retardait visiblement l'apparition de la feuille.
    private let neighbors: ShelfNeighbors

    init(targetRelease: Release, customCollection: [Release]? = nil) {
        self.targetRelease = targetRelease
        self.customCollection = customCollection
        let preferences = ShelfPreferencesStore.shared
        self.neighbors = ShelfPlacementViewModel().neighbors(
            for: targetRelease,
            customCollection: customCollection,
            strategy: preferences.sortStrategy,
            ignoreArticles: preferences.ignoreArticles,
            restrictToSameFolder: preferences.restrictToSameFolder,
            username: DiscogsAuthManager.shared.username
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if !premiumStore.isPremium {
                    VStack(spacing: 20) {
                        Spacer(minLength: 40)
                        PremiumLockedCard(
                            icon: "books.vertical.fill",
                            title: "Guide de rangement physique",
                            message: "Le calcul automatique de l'emplacement exact de chaque album dans ton meuble est une fonctionnalité réservée aux membres premium."
                        )
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                } else {
                    VStack(alignment: .leading, spacing: 22) {
                        // 1. En-tête : Emplacement chiffré & jauge relative dans le meuble
                        VStack(alignment: .leading, spacing: 8) {
                            SectionEyebrow(title: "Position dans le meuble", icon: "books.vertical.fill")

                            HStack(alignment: .center) {
                                // Les vinyles, CD et cassettes ne se rangent jamais ensemble (ni les
                                // 7" avec les 12") : rappelle explicitement quel espace de rangement
                                // physique est concerné par ce calcul de position.
                                Text(neighbors.category.displayName.uppercased())
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.spinlogPink)

                                Spacer()

                                scopeBadge
                            }

                            positionOverviewCard
                        }

                        // 2. Triptyque horizontal : Voisin gauche - Disque cible - Voisin droite
                        VStack(alignment: .leading, spacing: 8) {
                            SectionEyebrow(title: "Disques repères", icon: "square.split.3x1.fill")
                            horizontalTriptychSection
                        }

                        // 3. Règle de classement physique active
                        VStack(alignment: .leading, spacing: 8) {
                            SectionEyebrow(title: "Méthode de classement", icon: "slider.horizontal.3")
                            sortStrategyCard
                        }

                        Spacer(minLength: 16)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Guide de rangement")
            .navigationBarTitleDisplayMode(.inline)
            .searchDestinations()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
            .onAppear {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()

                Task {
                    await viewModel.prefetchMasterYearIfNeeded(
                        for: targetRelease,
                        usesMasterYear: preferences.sortStrategy.usesMasterYear
                    )
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Badge de périmètre de rangement

    /// Teinte orange adaptée : plus sombre et contrastée en mode clair pour une excellente lisibilité
    private var folderBadgeColor: Color {
        if colorScheme == .light {
            return Color(red: 0.72, green: 0.32, blue: 0.0)
        } else {
            return Color.orange
        }
    }

    private var scopeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: neighbors.scope.iconName)
                .font(.caption2.weight(.bold))
            Text(neighbors.scope.badgeText)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(neighbors.scope.isFolderRestricted ? folderBadgeColor : Color.appSecondaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            (neighbors.scope.isFolderRestricted ? folderBadgeColor : Color.primary)
                .opacity(colorScheme == .light ? 0.10 : 0.14),
            in: Capsule()
        )
    }

    // MARK: - 1. En-tête : Emplacement & Jauge dans le meuble

    private var positionOverviewCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("N° \(neighbors.positionIndex)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(positionSubheadline)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.appSecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)
            }

            // Jauge de progression horizontale
            if neighbors.totalCount > 1 {
                GeometryReader { geo in
                    let ratio = CGFloat(neighbors.positionIndex - 1) / CGFloat(max(neighbors.totalCount - 1, 1))
                    let width = geo.size.width

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 5)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.spinlogPink.opacity(0.7), Color.spinlogPink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(width * ratio, 6), height: 5)
                    }
                }
                .frame(height: 5)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .appleMusicGroupedCard()
    }

    // Le dossier (si le rangement y est limité) est déjà annoncé par `scopeBadge` en haut de
    // la fenêtre : pas besoin de le répéter ici.
    private var positionSubheadline: String {
        String(localized: "sur \(neighbors.totalCount) \(neighbors.category.lowercasedDisplayName)")
    }

    // MARK: - 2. Triptyque horizontal (Gauche - Centre - Droite)

    private var horizontalTriptychSection: some View {
        HStack(alignment: .top, spacing: 8) {
            // Disque précédent (Gauche) ou début
            if let prev = neighbors.previous {
                neighborColumn(release: prev, isLeft: true)
            } else {
                edgeColumn(
                    title: "Début du meuble",
                    subtitle: "Premier album",
                    icon: "arrow.left.to.line.compact",
                    color: .blue
                )
            }

            // Disque cible (Centre - surélevé et agrandi)
            targetColumn

            // Disque suivant (Droite) ou fin
            if let next = neighbors.next {
                neighborColumn(release: next, isLeft: false)
            } else {
                edgeColumn(
                    title: "Fin du meuble",
                    subtitle: "Dernier album",
                    icon: "arrow.right.to.line.compact",
                    color: .purple
                )
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .appleMusicGroupedCard()
    }

    /// Colonne centrale : le disque cible à ranger
    private var targetColumn: some View {
        VStack(spacing: 8) {
            // Badge d'action
            HStack(spacing: 3) {
                Image(systemName: "arrow.down")
                    .font(.caption2.weight(.bold))
                Text("ICI")
                    .font(.caption2.weight(.heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.buttonPinkTop, Color.buttonPinkBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: Color.spinlogPink.opacity(0.35), radius: 5, y: 2)

            // Pochette centrale plus grande avec bordure rose
            AsyncCoverImage(url: targetRelease.primaryImageURL, cornerRadius: 10, targetSize: 104)
                .frame(width: 104, height: 104)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.spinlogPink, lineWidth: 2)
                )
                .shadow(color: Color.spinlogPink.opacity(0.25), radius: 8, y: 4)

            // Titre, Artiste et Année
            VStack(spacing: 2) {
                Text(targetRelease.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !targetRelease.artistNames.isEmpty {
                    Text(targetRelease.artistNames)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.spinlogPink)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }

                if let effYear = targetRelease.effectiveShelfYear(useOriginalYear: preferences.sortStrategy.usesMasterYear), effYear > 0 {
                    Text(String(effYear))
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.appSecondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Colonne d'un disque voisin (Gauche ou Droite)
    private func neighborColumn(release: Release, isLeft: Bool) -> some View {
        NavigationLink(value: SearchDestination.release(release.id, coverURL: release.primaryImageURL)) {
            VStack(spacing: 8) {
                // Badge de repère
                HStack(spacing: 3) {
                    if isLeft {
                        Image(systemName: "arrow.left")
                            .font(.caption2.weight(.bold))
                    }
                    Text(isLeft ? "À GAUCHE" : "À DROITE")
                        .font(.caption2.weight(.bold))
                    if !isLeft {
                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.bold))
                    }
                }
                .foregroundStyle(isLeft ? Color.blue : Color.purple)
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background((isLeft ? Color.blue : Color.purple).opacity(0.12), in: Capsule())

                // Pochette
                AsyncCoverImage(url: release.primaryImageURL, cornerRadius: 8, targetSize: 76)
                    .frame(width: 76, height: 76)
                    .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)

                // Métadonnées
                VStack(spacing: 2) {
                    Text(release.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !release.artistNames.isEmpty {
                        Text(release.artistNames)
                            .font(.caption2)
                            .foregroundStyle(Color.appSecondaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                    }

                    if let effYear = release.effectiveShelfYear(useOriginalYear: preferences.sortStrategy.usesMasterYear), effYear > 0 {
                        Text(String(effYear))
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(Color.appTertiaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// Colonne pour le Début ou la Fin de meuble
    private func edgeColumn(title: LocalizedStringResource, subtitle: LocalizedStringResource, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(String(localized: subtitle).uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background(color.opacity(0.12), in: Capsule())

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.06))
                    .frame(width: 76, height: 76)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(color.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )

                VStack(spacing: 3) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(color)

                    Text(title)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(color)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(width: 64)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 3. Règle de classement active

    private var sortStrategyCard: some View {
        Button {
            dismiss()
            TabNavigationCoordinator.shared.openSettingsAtOrganizationSection()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preferences.sortStrategy.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(preferences.ignoreArticles ? "Ignore les articles (The, Les…)" : "Prend en compte les articles")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("Modifier")
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                }
                .foregroundStyle(Color.spinlogPink)
            }
            .padding(14)
            .appleMusicGroupedCard()
        }
        .buttonStyle(.plain)
    }
}
