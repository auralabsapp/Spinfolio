import SwiftUI

/// Vue guidant l'utilisateur pour ranger physiquement son vinyle dans son meuble,
/// avec une présentation horizontale élégante mettant en scène le disque cible au centre
/// entouré de ses 2 voisins immédiats (gauche et droite).
struct ShelfPlacementView: View {
    let targetRelease: Release
    var customCollection: [Release]? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var preferences = ShelfPreferencesStore.shared
    @State private var premiumStore = PremiumStore.shared
    @State private var authManager = DiscogsAuthManager.shared
    @State private var viewModel = ShelfPlacementViewModel()
    /// Pulsation du disque central après un toucher (voir `pulseTarget`).
    @State private var isTargetPulsing = false
    /// Passe à vrai une seule fois, juste après le premier affichage : déclenche les animations
    /// d'entrée (compteur, jauge, disques). Jamais réarmé, pour que revenir d'une fiche ouverte
    /// depuis un disque repère ne les rejoue pas.
    @State private var hasAppeared = false
    /// Position affichée dans le compteur : part de 0 et rejoint la vraie position à l'entrée.
    @State private var displayedPosition = 0
    /// Légère pulsation continue du repère « ICI ».
    @State private var isBadgeBeating = false
    /// Respiration lente et permanente de la pochette cible, lancée une fois les disques en place.
    @State private var isCoverBreathing = false
    @State private var pulseResetTask: Task<Void, Never>?

    /// Calculés une seule fois à l'ouverture, plutôt qu'à chaque image de rendu comme le ferait
    /// une propriété calculée ordinaire : cette recherche relit et décode toute la collection
    /// locale puis la trie entièrement (voir `ShelfPlacementService.findNeighborsInLocalStore`).
    /// Chargés de façon asynchrone (décodage hors du fil principal) : auparavant calculés dans
    /// `init`, en synchrone, ce qui retardait l'apparition de la feuille sur une grosse collection.
    @State private var loadedNeighbors: ShelfNeighbors?

    /// Valeur d'attente, jamais affichée : le contenu n'apparaît qu'une fois `loadedNeighbors` connu.
    private var neighbors: ShelfNeighbors {
        loadedNeighbors ?? ShelfNeighbors(
            target: targetRelease,
            previous: nil,
            next: nil,
            strategy: preferences.sortStrategy,
            category: targetRelease.shelfMediaCategory,
            totalCount: 1,
            positionIndex: 1,
            scope: .allFolders
        )
    }

    init(targetRelease: Release, customCollection: [Release]? = nil) {
        self.targetRelease = targetRelease
        self.customCollection = customCollection
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
                } else if loadedNeighbors == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    VStack(alignment: .leading, spacing: 22) {
                        // 1. En-tête : Emplacement chiffré & jauge relative dans le meuble
                        VStack(alignment: .leading, spacing: 8) {
                            SectionEyebrow(title: "Position dans le meuble", icon: "books.vertical.fill", isPremiumFeature: true)

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
            .background(Color.appBackground.ignoresSafeArea())
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
        .task {
            guard loadedNeighbors == nil else { return }
            loadedNeighbors = await viewModel.neighbors(
                for: targetRelease,
                customCollection: customCollection,
                strategy: preferences.sortStrategy,
                ignoreArticles: preferences.ignoreArticles,
                restrictToSameFolder: preferences.restrictToSameFolder,
                username: authManager.username
            )
            playEntranceIfNeeded()
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
                Text("N° \(displayedPosition)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    // Le chiffre défile de 0 jusqu'à la position du disque à l'ouverture.
                    .contentTransition(.numericText(value: Double(displayedPosition)))

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
                    // La jauge se remplit en même temps que le compteur monte.
                    let ratio = hasAppeared
                        ? CGFloat(neighbors.positionIndex - 1) / CGFloat(max(neighbors.totalCount - 1, 1))
                        : 0
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
                            .animation(reduceMotion ? nil : .smooth(duration: 0.9), value: hasAppeared)
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
            Group {
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
            }
            // Les voisins arrivent d'abord, de chaque côté.
            .shelfEntrance(isVisible: hasAppeared, offset: CGSize(width: -44, height: 0), delay: 0.15)

            // Disque cible (Centre - surélevé et agrandi) : il descend entre ses voisins en dernier.
            targetColumn
                .shelfEntrance(isVisible: hasAppeared, offset: CGSize(width: 0, height: -46), delay: 0.5, startScale: 0.88)

            // Disque suivant (Droite) ou fin
            Group {
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
            .shelfEntrance(isVisible: hasAppeared, offset: CGSize(width: 44, height: 0), delay: 0.15)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .appleMusicGroupedCard()
    }

    /// Colonne centrale : le disque cible à ranger (voir `ShelfTargetColumn`).
    private var targetColumn: some View {
        ShelfTargetColumn(
            release: targetRelease,
            yearText: targetYearText,
            isPulsing: isTargetPulsing,
            isCoverBreathing: isCoverBreathing,
            isBadgeBeating: isBadgeBeating,
            onTap: pulseTarget
        )
    }

    /// Année affichée sous le titre du disque cible, selon la règle de classement active.
    private var targetYearText: String? {
        guard let year = targetRelease.effectiveShelfYear(useOriginalYear: preferences.sortStrategy.usesMasterYear), year > 0 else { return nil }
        return String(year)
    }

    /// Lance l'entrée une seule fois : compteur qui monte, jauge qui se remplit, disques qui arrivent,
    /// puis battement discret du repère « ICI ». Légèrement différé pour que l'état de départ
    /// (masqué, compteur à 0) soit d'abord affiché. Avec « Réduire les animations », tout est direct.
    private func playEntranceIfNeeded() {
        guard !hasAppeared else { return }
        guard !reduceMotion else {
            displayedPosition = neighbors.positionIndex
            hasAppeared = true
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            hasAppeared = true
            withAnimation(.smooth(duration: 0.9)) {
                displayedPosition = neighbors.positionIndex
            }
            // Une fois les disques en place : la pochette se met à respirer lentement, en continu
            // (grossit puis reprend sa taille), et le repère « ICI » à battre discrètement.
            try? await Task.sleep(for: .milliseconds(1100))
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                isCoverBreathing = true
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isBadgeBeating = true
            }
        }
    }

    /// Le testeur touche instinctivement le disque central : on confirme que le toucher est
    /// reconnu (rebond + retour haptique) sans rien ouvrir, puisque ce disque est celui de la
    /// fiche d'où l'on vient. Avec « Réduire les animations », seule la bordure change.
    private func pulseTarget() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        pulseResetTask?.cancel()
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .shelfTargetPulse) {
            isTargetPulsing = true
        }
        pulseResetTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .shelfTargetPulse) {
                isTargetPulsing = false
            }
        }
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
                AsyncCoverImage(url: release.primaryImageURL, cornerRadius: AppLayout.coverCornerRadius, targetSize: 76)
                    .frame(width: 76, height: 76)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppLayout.coverCornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 3)
                    .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)

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
