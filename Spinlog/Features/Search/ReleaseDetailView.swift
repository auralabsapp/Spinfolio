import SwiftUI

/// Route unique pour toutes les sheets de cet écran qui dépendent de la release chargée.
/// Chaque cas capture la `Release` (ou l'URL) au moment du tap plutôt que de la relire depuis
/// un `@State private var release: Release?` séparé au moment où SwiftUI construit le contenu
/// du sheet — cela évite la course entre un `Bool` de présentation et cet état optionnel,
/// responsable du bug de webview vide déjà rencontré sur UserProfileSheet.
private enum ReleaseSheetRoute: Identifiable {
    case marketplace(Release)
    case safari(URL)
    case otherInfo(Release)
    case media(Release)
    case shelfPlacement(Release)

    var id: String {
        switch self {
        case .marketplace(let release): return "marketplace-\(release.id)"
        case .safari(let url): return "safari-\(url.absoluteString)"
        case .otherInfo(let release): return "otherInfo-\(release.id)"
        case .media(let release): return "media-\(release.id)"
        case .shelfPlacement(let release): return "shelfPlacement-\(release.id)"
        }
    }
}

struct ReleaseDetailView: View {
    let releaseId: Int
    var initialCoverURL: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var viewModel = ReleaseDetailViewModel()
    @State private var actions = ReleaseActions()
    @State private var selectedItemForNotes: CollectionItem?
    @State private var activeSheet: ReleaseSheetRoute?
    @State private var premiumStore = PremiumStore.shared
    @State private var shelfPreferences = ShelfPreferencesStore.shared
    @State private var showingPremiumSheet = false
    @State private var imageViewerRequest: ImageViewerRequest?
    @State private var scrollOffsetY: CGFloat = 0
    /// Déclenche le léger « pop » de la jaquette après un ajout à la collection ou à la wantlist.
    @State private var heroPop = 0
    /// Passe à vrai une fois la fiche chargée : les sections arrivent alors en cascade (une seule
    /// fois, pas à chaque retour sur l'écran).
    @State private var sectionsRevealed = false

    private var infoBackgroundColor: Color {
        if let averageColor = viewModel.averageColor {
            return averageColor.infoBackgroundColor(for: colorScheme)
        }
        return Color(uiColor: .systemBackground)
    }

    /// Disparition très douce et progressive du titre et de l'artiste lors du swipe up
    private var titleOpacity: Double {
        let scrollUp = Double(max(0, scrollOffsetY))
        let fadeDistance: Double = 200.0
        let progress = min(1.0, scrollUp / fadeDistance)
        // Courbe d'atténuation cosinus pour une transition veloutée sans coupure abrupte
        return max(0.0, (1.0 + cos(.pi * progress)) / 2.0)
    }

    /// Fondu entre la jaquette et la zone d'informations : de nombreux paliers échantillonnés
    /// sur une courbe cosinus (au lieu de quelques points reliés linéairement) pour éviter
    /// les "coudes" visibles d'un dégradé grossier.
    private var heroToInfoGradient: LinearGradient {
        let stopCount = 24
        let stops: [Gradient.Stop] = (0...stopCount).map { step in
            let location = Double(step) / Double(stopCount)
            let eased = (1.0 - cos(.pi * location)) / 2.0
            return .init(color: infoBackgroundColor.opacity(eased), location: location)
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        content
            .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .tabBar)
            .background(infoBackgroundColor.ignoresSafeArea())
            .disablesContentPopGesture()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.medium))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                    }
                    .accessibilityLabel("Retour")
                }

                if let url = viewModel.release?.discogsWebURL {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.body.weight(.medium))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                        }
                        .accessibilityLabel("Partager la release")

                        Button {
                            activeSheet = .safari(url)
                        } label: {
                            Image(systemName: "safari")
                                .font(.body.weight(.medium))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                        }
                        .accessibilityLabel("Ouvrir sur Discogs")
                    }
                }
            }
            .sheet(item: $selectedItemForNotes) { item in
                CollectionItemEditSheet(
                    item: item,
                    fields: actions.collectionFields,
                    folders: actions.folders,
                    onSaved: { rating, notes in
                        Task { await actions.applyEditedValues(rating: rating, notes: notes, instanceId: item.instanceId) }
                    },
                    onFolderChanged: { item, newFolderId in
                        Task { await actions.moveInstance(item, toFolderId: newFolderId) }
                    },
                    onDelete: {
                        await actions.removeInstance(item)
                    },
                    onSaveFailedAfterDismiss: { message in
                        actions.message = message
                    }
                )
            }
            .sheet(item: $activeSheet) { route in
                switch route {
                case .marketplace(let release):
                    MarketplaceSheet(releaseId: release.id)
                case .safari(let url):
                    SafariView(url: url)
                case .otherInfo(let release):
                    ReleaseOtherInfoSheet(release: release)
                case .media(let release):
                    ReleaseMediaSheet(images: release.images, videos: release.videos)
                case .shelfPlacement(let release):
                    ShelfPlacementView(targetRelease: release)
                }
            }
            .premiumFeaturesSheet(isPresented: $showingPremiumSheet)
            .fullScreenCover(item: $imageViewerRequest) { request in
                ImageViewerView(images: viewModel.release?.images ?? [], startIndex: request.startIndex)
            }
            .onAppear {
                actions.prepareInitialStatus(releaseId: releaseId)
                if let cached = ReleaseColorCache.shared.color(forReleaseId: releaseId) {
                    viewModel.averageColor = cached
                } else if let initialCoverURL, let cached = ReleaseColorCache.shared.color(forURL: initialCoverURL) {
                    viewModel.averageColor = cached
                }
            }
            .task { await viewModel.loadIfNeeded(releaseId: releaseId, actions: actions) }
            .onChange(of: viewModel.release?.id, initial: true) { _, loadedId in
                if loadedId != nil { sectionsRevealed = true }
            }
            // « Pop » de la jaquette à l'ajout ; le retour haptique de l'ajout ou du retrait est joué
            // avec la bulle de confirmation (`LibraryMembershipStore`), le même sur tous les écrans.
            .onChange(of: actions.lastFeedbackEvent) { _, event in
                guard let event, event.kind.isAddition else { return }
                heroPop += 1
            }
    }

    private func triggerListeningLog() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // Lance la Live Activity / Dynamic Island ET le mini-lecteur platine immédiatement
        let title = viewModel.release?.title ?? "Vinyle"
        let artist = viewModel.release?.artistNames ?? ""
        let cover = viewModel.release?.primaryImageURL ?? initialCoverURL
        NowPlayingActivityManager.shared.startListening(
            releaseId: releaseId,
            albumTitle: title,
            artistName: artist,
            coverURL: cover
        )
    }

    private func stopListeningSession() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await NowPlayingActivityManager.shared.endActivity(for: releaseId)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ReleaseDetailSkeleton()
                .background(infoBackgroundColor.ignoresSafeArea())
                .transition(.opacity)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView {
                Label("Impossible de charger la release", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Réessayer") {
                    Task { await viewModel.load(releaseId: releaseId, actions: actions) }
                }
                .buttonStyle(.glassProminent)
                .foregroundStyle(Color.onAccent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(infoBackgroundColor.ignoresSafeArea())
        } else if let release = viewModel.release {
            ScrollView {
                VStack(spacing: 0) {
                    ReleaseHeroCover(
                        release: release,
                        releaseId: releaseId,
                        initialCoverURL: initialCoverURL,
                        backgroundColor: infoBackgroundColor,
                        heroPop: heroPop,
                        onAverageColor: { color in
                            withAnimation(.easeInOut(duration: 0.35)) {
                                viewModel.averageColor = color
                            }
                        },
                        onTap: {
                            guard let images = release.images, !images.isEmpty else { return }
                            imageViewerRequest = ImageViewerRequest(startIndex: 0)
                        }
                    )

                    // Zone d'informations complète (Titre/Artiste avec dégradé doux + Contenu)
                    VStack(spacing: 0) {
                        // Titre de l'album et nom de l'artiste :
                        // Remontés sur la jaquette, centrés, et disparaissant très progressivement lors du swipe up
                        VStack(spacing: 6) {
                            Text(release.title)
                                .font(.title.bold())
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                // Deux ombres superposées : un contour net et rapproché pour détacher
                                // les lettres de la jaquette, plus un halo large et diffus pour rester
                                // lisible même sur un fond clair.
                                .shadow(color: .black.opacity(0.9), radius: 3, x: 0, y: 1)
                                .shadow(color: .black.opacity(0.7), radius: 14, x: 0, y: 4)

                            if let artists = release.artists, !artists.isEmpty {
                                ReleaseArtistCreditsRow(artists: artists)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, 38)
                        .padding(.bottom, 32)
                        .opacity(titleOpacity)
                        .background(heroToInfoGradient)

                        // Zone d'informations : sans bords arrondis, couleur moyenne déduite de la jaquette
                        VStack(alignment: .leading, spacing: 32) {
                            // 0. Fiche reconstruite depuis le cache local faute de réseau : certaines
                            // sections (tracklist, communauté, marketplace, vidéos) resteront vides.
                            if viewModel.isOfflineFallback {
                                OfflineBannerView(customMessage: String(localized: "Fiche limitée depuis ta collection"))
                            }

                            // 1. Boutons d'actions rapides tactiles : "En collection" et "Wantlist"
                            ReleaseQuickActionsBar(
                                releaseId: releaseId,
                                release: release,
                                actions: actions,
                                onShowShelfPlacement: {
                                    handleShowShelfPlacement(for: release)
                                }
                            )
                            .releaseSectionEntrance(sectionsRevealed, index: 0)

                            // 1.1 Guide de rangement : confirmation immédiate après ajout à la collection
                            if actions.justAddedReleaseId == releaseId {
                                ReleasePostAddShelfPlacementCard(
                                    fallback: release,
                                    actions: actions,
                                    onOpenShelfPlacement: { activeSheet = .shelfPlacement($0) }
                                )
                            }

                            // 2. Section "Mes exemplaires" (propre aux exemplaires possédés dans la collection)
                            if actions.isInCollection && !actions.collectionInstances.isEmpty {
                                MyItemCard(
                                    instances: actions.collectionInstances,
                                    releaseId: release.id,
                                    release: release,
                                    actions: actions,
                                    onOpenNotes: { item in
                                        selectedItemForNotes = item
                                    },
                                    onShelfPlacement: { item in
                                        handleShowShelfPlacement(for: Release(from: item))
                                    }
                                )
                                .releaseSectionEntrance(sectionsRevealed, index: 1)
                            }

                            // 2bis. Emplacement physique dans le meuble : section à part entière
                            // (plutôt qu'une ligne noyée dans "Mes exemplaires") pour lui donner
                            // le même statut visuel que les autres fonctionnalités de la page.
                            // La bannière reste affichée même quand 2 exemplaires sont dans 2
                            // dossiers différents (rangement ambigu) : `shelfPlacementRow` en
                            // adapte alors le sous-titre et la rend non cliquable, au lieu de la
                            // remplacer par un texte à part — voir `commonInstanceFolderRelease`.
                            if actions.isInCollection {
                                VStack(alignment: .leading, spacing: 12) {
                                    SectionEyebrow(title: "Rangement physique", icon: "books.vertical.fill")
                                    ReleaseShelfPlacementRow(
                                        release: commonInstanceFolderRelease,
                                        onOpen: { activeSheet = .shelfPlacement($0) }
                                    )
                                }
                                .releaseSectionEntrance(sectionsRevealed, index: 2)
                            }

                            // 2ter. Journal d'écoute : réservé aux disques possédés (on n'écoute pas, sur sa
                            // platine, un disque qu'on n'a pas).
                            if actions.isInCollection {
                                VStack(alignment: .leading, spacing: 12) {
                                    SectionEyebrow(title: "Mes écoutes sur platine", icon: "opticaldisc.fill")
                                    ListeningLogCard(
                                        releaseId: releaseId,
                                        onLogListening: {
                                            triggerListeningLog()
                                        },
                                        onStopListening: {
                                            stopListeningSession()
                                        }
                                    )
                                }
                                .releaseSectionEntrance(sectionsRevealed, index: 3)
                            }

                            // 2quater. Note personnelle de la release (partagée par Discogs entre tous les exemplaires)
                            if actions.isInCollection && !actions.collectionInstances.isEmpty {
                                ReleaseRatingCard(
                                    rating: actions.collectionInstances.first?.rating ?? 0,
                                    isUpdating: actions.isUpdatingRating,
                                    onSetRating: { newRating in
                                        Task { await actions.updateReleaseRating(newRating) }
                                    }
                                )
                                .releaseSectionEntrance(sectionsRevealed, index: 4)
                            }

                            // 3. Infos Discogs : données propres à la release, communes à tous les exemplaires
                            // (par opposition aux sections 1-2quater, propres à l'utilisateur).
                            ReleaseDiscogsInfoSection(
                                release: release,
                                initialCoverURL: initialCoverURL,
                                onShowMarketplace: { activeSheet = .marketplace(release) },
                                onShowMedia: { activeSheet = .media(release) },
                                onShowOtherInfo: { activeSheet = .otherInfo(release) }
                            )
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)
                        .padding(.bottom, 64)
                        .background(infoBackgroundColor)
                        .animation(.easeInOut(duration: 0.35), value: infoBackgroundColor)
                    }
                    .padding(.top, -165)
                }
            }
            .coordinateSpace(name: "releaseScroll")
            // `@Sendable` : sans ça, la closure hérite de l'isolation MainActor du module, alors que
            // SwiftUI peut l'évaluer sur son fil de rendu asynchrone (`AsyncRenderer`) — l'app
            // s'arrêtait (`dispatch_assert_queue_fail`) au relayout animé du lancement d'une écoute.
            .onScrollGeometryChange(for: CGFloat.self) { @Sendable geo in
                geo.contentOffset.y
            } action: { _, newValue in
                scrollOffsetY = newValue
            }
            .swipeActionsContainerIfAvailable()
            .ignoresSafeArea(edges: .all)
            .background(infoBackgroundColor.ignoresSafeArea())
            .onAppear {
                TabNavigationCoordinator.shared.registerTopDestination(.release(releaseId, coverURL: initialCoverURL))
            }
            .onDisappear {
                TabNavigationCoordinator.shared.unregisterTopDestination(.release(releaseId, coverURL: initialCoverURL))
            }
            .transition(.opacity)
        }
    }

    /// Release reconstruite avec le dossier commun à tous les exemplaires possédés, pour la
    /// section "Rangement physique" générique : `nil` seulement si "Limiter au dossier Discogs"
    /// est actif ET que les exemplaires sont répartis dans plusieurs dossiers différents — le
    /// rangement devient alors ambigu (voir le balayage par exemplaire dans "Mes exemplaires").
    /// Si le réglage est désactivé, le dossier n'a aucune influence sur le résultat : la
    /// section générique reste donc pertinente quel que soit le nombre de dossiers distincts.
    private var commonInstanceFolderRelease: Release? {
        guard let first = actions.collectionInstances.first else { return nil }
        guard shelfPreferences.restrictToSameFolder,
              Set(actions.collectionInstances.map(\.folderId)).count > 1 else {
            return Release(from: first)
        }
        return nil
    }

    private func handleShowShelfPlacement(for release: Release) {
        if !premiumStore.isPremium {
            showingPremiumSheet = true
        } else {
            activeSheet = .shelfPlacement(release)
        }
    }

}

private extension View {
    /// Entrée en cascade des sections de la fiche : chacune arrive un peu après la précédente.
    func releaseSectionEntrance(_ revealed: Bool, index: Int) -> some View {
        shelfEntrance(isVisible: revealed, offset: CGSize(width: 0, height: 18), delay: 0.07 * Double(index))
    }
}

#Preview {
    NavigationStack {
        ReleaseDetailView(releaseId: 249504)
    }
}
