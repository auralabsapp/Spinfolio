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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewModel = ReleaseDetailViewModel()
    @State private var actions = ReleaseActions()
    @State private var selectedItemForNotes: CollectionItem?
    @State private var activeSheet: ReleaseSheetRoute?
    @State private var premiumStore = PremiumStore.shared
    @State private var shelfPreferences = ShelfPreferencesStore.shared
    @State private var showingPremiumSheet = false
    @State private var imageViewerRequest: ImageViewerRequest?
    @State private var scrollOffsetY: CGFloat = 0

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
            .task { await viewModel.load(releaseId: releaseId, actions: actions) }
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
            releaseDetailSkeleton
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(infoBackgroundColor.ignoresSafeArea())
        } else if let release = viewModel.release {
            ScrollView {
                VStack(spacing: 0) {
                    parallaxHeroCover(for: release)

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
                                artistCreditsRow(artists)
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

                            // 1.1 Guide de rangement : confirmation immédiate après ajout à la collection
                            if actions.justAddedReleaseId == releaseId {
                                postAddShelfPlacementCard(fallback: release)
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
                                    shelfPlacementRow(for: commonInstanceFolderRelease)
                                }
                            }

                            // 2ter. Journal d'écoute (disponible pour toute release)
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

                            // 2quater. Note personnelle de la release (partagée par Discogs entre tous les exemplaires)
                            if actions.isInCollection && !actions.collectionInstances.isEmpty {
                                ReleaseRatingCard(
                                    rating: actions.collectionInstances.first?.rating ?? 0,
                                    isUpdating: actions.isUpdatingRating,
                                    onSetRating: { newRating in
                                        Task { await actions.updateReleaseRating(newRating) }
                                    }
                                )
                            }

                            // 3. Section "Infos Discogs sur la release" : regroupe toutes les
                            // données propres à la release et communes à tous les exemplaires
                            // (par opposition aux sections 1-2bis, propres à l'utilisateur/ses
                            // exemplaires). Hiérarchie portée par l'espacement et la typographie
                            // (SectionEyebrow), sans conteneur ni fond de carte, conformément au
                            // style plat des pages de détail Apple Music/iOS.
                            VStack(alignment: .leading, spacing: 32) {
                                SectionEyebrow(title: "Infos Discogs sur la release", icon: "info.circle.fill")

                                VStack(alignment: .leading, spacing: 32) {
                                    if let community = release.community {
                                        CommunityStatsBar(community: community)
                                    }

                                    let genres = release.genres ?? []
                                    let styles = release.styles ?? []
                                    if !genres.isEmpty || !styles.isEmpty {
                                        GenreTagsRow(genres: genres, styles: styles)
                                    }

                                    ReleaseInfoCard(release: release)

                                    if let tracklist = release.tracklist, !tracklist.isEmpty {
                                        TracklistSection(
                                            tracklist: tracklist,
                                            artistName: release.artistNames,
                                            albumTitle: release.title,
                                            coverURL: release.primaryImageURL ?? initialCoverURL,
                                            destination: .release(release.id, coverURL: release.primaryImageURL ?? initialCoverURL)
                                        )
                                    }

                                    if let numForSale = release.numForSale, numForSale > 0 {
                                        MarketplaceButton(numForSale: numForSale, lowestPrice: release.lowestPrice) {
                                            activeSheet = .marketplace(release)
                                        }
                                    }

                                    if hasMedia(for: release) {
                                        Button {
                                            activeSheet = .media(release)
                                        } label: {
                                            HStack(spacing: 12) {
                                                Image(systemName: "photo.on.rectangle.angled")
                                                    .font(.title3)
                                                    .foregroundStyle(Color.spinlogPink)
                                                    .frame(width: 28, height: 28)

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("Photos et vidéos")
                                                        .font(.subheadline.weight(.semibold))
                                                        .foregroundStyle(.primary)

                                                    if !mediaSummary(for: release).isEmpty {
                                                        Text(mediaSummary(for: release))
                                                            .font(.caption)
                                                            .foregroundStyle(Color.appSecondaryText)
                                                    }
                                                }

                                                Spacer(minLength: 0)

                                                Image(systemName: "chevron.right")
                                                    .font(.caption)
                                                    .foregroundStyle(Color.appTertiaryText)
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 12)
                                            .appleMusicGroupedCard()
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    // Section Notes placée sous les photos et vidéos avec déplier/replier
                                    if let notes = release.notes, !notes.isEmpty {
                                        NotesSection(notes: notes)
                                    }

                                    // Section cliquable "Autres informations" qui ouvre une bottom sheet avec
                                    // les identifiants, entreprises de fabrication et crédits
                                    if hasOtherInfo(for: release) {
                                        Button {
                                            activeSheet = .otherInfo(release)
                                        } label: {
                                            HStack(spacing: 12) {
                                                Image(systemName: "info.circle")
                                                    .font(.title3)
                                                    .foregroundStyle(Color.spinlogPink)
                                                    .frame(width: 28, height: 28)

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("Autres informations")
                                                        .font(.subheadline.weight(.semibold))
                                                        .foregroundStyle(.primary)

                                                    Text(otherInfoSummary(for: release))
                                                        .font(.caption)
                                                        .foregroundStyle(Color.appSecondaryText)
                                                        .lineLimit(1)
                                                }

                                                Spacer(minLength: 0)

                                                Image(systemName: "chevron.right")
                                                    .font(.caption)
                                                    .foregroundStyle(Color.appTertiaryText)
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 12)
                                            .appleMusicGroupedCard()
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                if let url = release.discogsWebURL {
                                    DiscogsAttributionLink(url: url)
                                }
                            }
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
            .onScrollGeometryChange(for: CGFloat.self) { geo in
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

    /// Gabarit neutre affiché pendant le chargement, à la place d'une icône de chargement :
    /// pochette en plein bord (comme la vraie jaquette héro, pas de titre/artiste superposé tant
    /// qu'on ne l'a pas), les 2 boutons d'action, puis des sections génériques titre + contenu
    /// (voir `SkeletonBlock`), pour que l'apparition du contenu réel ne fasse pas sauter la page.
    private var releaseDetailSkeleton: some View {
        ScrollView {
            VStack(spacing: 0) {
                SkeletonBlock(cornerRadius: 0)
                    .aspectRatio(1, contentMode: .fit)
                    .padding(.bottom, 24)

                VStack(alignment: .leading, spacing: 32) {
                    HStack(spacing: 10) {
                        SkeletonBlock(cornerRadius: 21, height: 42)
                        SkeletonBlock(cornerRadius: 21, height: 42)
                    }

                    SkeletonSection(contentHeight: 70)
                    SkeletonSection(contentHeight: 130)
                    SkeletonSection(contentHeight: 160)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollDisabled(true)
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

    /// Emplacement physique dans le meuble.
    /// En mode non-premium, affiche une carte verrouillée identique au compteur de lectures.
    /// `release` est `nil` quand le rangement est ambigu (exemplaires répartis dans plusieurs
    /// dossiers, restriction active — voir `commonInstanceFolderRelease`) : la bannière reste
    /// affichée mais devient non cliquable, avec un sous-titre invitant à balayer l'exemplaire
    /// concerné dans "Mes exemplaires" plutôt que de lancer un rangement qui serait arbitraire.
    @ViewBuilder
    private func shelfPlacementRow(for release: Release?) -> some View {
        if !premiumStore.isPremium {
            PremiumLockedCard(
                icon: "books.vertical.fill",
                title: "Emplacement de cet album",
                message: "Passe premium pour savoir instantanément où intercaler ce disque dans ton meuble."
            )
        } else if let release {
            Button {
                activeSheet = .shelfPlacement(release)
            } label: {
                shelfPlacementRowContent(
                    subtitle: "Voir sa place exacte entre ses deux voisins",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        } else {
            shelfPlacementRowContent(
                subtitle: SwipeActionsSupport.isAvailable
                    ? String(localized: "Balaie l'exemplaire concerné vers la gauche dans « Mes exemplaires » pour voir où le ranger")
                    : String(localized: "Maintiens le doigt sur l'exemplaire concerné dans « Mes exemplaires » pour voir où le ranger"),
                showsChevron: false
            )
        }
    }

    private func shelfPlacementRowContent(subtitle: String, showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .font(.title3)
                .foregroundStyle(Color.spinlogPink)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Emplacement de cet album")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            }

            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.appTertiaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .appleMusicGroupedCard()
    }

    /// `fallback` (la release générique, sans dossier) n'est utilisée que si l'exemplaire
    /// qui vient d'être ajouté n'est, improbablement, pas encore retrouvable dans
    /// `actions.collectionInstances` — sinon ce dernier porte le vrai dossier choisi,
    /// indispensable pour un rangement restreint au dossier.
    private func postAddShelfPlacementCard(fallback release: Release) -> some View {
        let targetRelease: Release
        if let lastInstance = actions.collectionInstances.last {
            targetRelease = Release(from: lastInstance)
        } else {
            targetRelease = release
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Ajouté à ta collection !")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    withAnimation {
                        actions.justAddedReleaseId = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.appSecondaryText)
                        .padding(6)
                }
                .accessibilityLabel("Masquer ce message")
            }

            if !premiumStore.isPremium {
                PremiumLockedCard(
                    icon: "books.vertical.fill",
                    title: "Emplacement de cet album",
                    message: "Passe premium pour savoir instantanément où intercaler ce disque dans ton meuble."
                )
            } else {
                Text("\(AppInfo.name) a déterminé l'emplacement exact de ce disque dans ton meuble.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)

                Button {
                    // Masque l'encart "Ajouté à ta collection !" : une fois qu'on a demandé
                    // l'emplacement, ce rappel n'a plus d'utilité et ne doit pas rester affiché
                    // derrière la feuille de rangement (ni persister une fois celle-ci refermée).
                    withAnimation {
                        actions.justAddedReleaseId = nil
                    }
                    activeSheet = .shelfPlacement(targetRelease)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "books.vertical.fill")
                        Text("Emplacement de cet album")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Color.spinlogPink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .appleMusicGroupedCard()
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.spinlogPink.opacity(0.35), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private func hasOtherInfo(for release: Release) -> Bool {
        (release.extraartists?.isEmpty == false) ||
        (release.companies?.isEmpty == false) ||
        (release.identifiers?.isEmpty == false)
    }

    private func otherInfoSummary(for release: Release) -> String {
        var parts: [String] = []
        if let credits = release.extraartists, !credits.isEmpty {
            parts.append(String(localized: "Crédits (\(credits.count))"))
        }
        if let companies = release.companies, !companies.isEmpty {
            parts.append(String(localized: "Fabrication (\(companies.count))"))
        }
        if let identifiers = release.identifiers, !identifiers.isEmpty {
            parts.append(String(localized: "Identifiants (\(identifiers.count))"))
        }
        return parts.joined(separator: " · ")
    }

    private func hasMedia(for release: Release) -> Bool {
        additionalImagesCount(for: release) > 0 || (release.videos?.isEmpty == false)
    }

    private func additionalImagesCount(for release: Release) -> Int {
        guard let images = release.images, images.count > 1 else { return 0 }
        return images.count
    }

    private func mediaSummary(for release: Release) -> String {
        var parts: [String] = []
        let imagesCount = additionalImagesCount(for: release)
        if imagesCount > 0 {
            parts.append(String(localized: "\(imagesCount) photos"))
        }
        if let videosCount = release.videos?.count, videosCount > 0 {
            parts.append(String(localized: "\(videosCount) vidéos"))
        }
        return parts.joined(separator: " · ")
    }

    /// Remplace l'ancien texte unique `release.artistNames` : chaque artiste devient son propre
    /// lien vers sa fiche (`ArtistDetailView`), séparés par le connecteur Discogs (`join`, ex:
    /// "&", "Featuring") en texte brut non cliquable — même principe que `CreditsSection`
    /// plus bas dans ce fichier. Non-wrapping par simplicité (la quasi-totalité des releases ont
    /// 1 à 3 artistes) ; au-delà, le nom tronque proprement plutôt que de retourner à la ligne.
    private func artistCreditsRow(_ artists: [ReleaseArtist]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(artists.enumerated()), id: \.offset) { index, artist in
                NavigationLink(value: SearchDestination.artist(artist.id)) {
                    Text(artist.displayName)
                }
                .buttonStyle(.plain)

                if index < artists.count - 1 {
                    let join = artist.join?.trimmingCharacters(in: .whitespaces) ?? ""
                    Text(join.isEmpty ? "," : join)
                }
            }
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(.white.opacity(0.92))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .shadow(color: .black.opacity(0.9), radius: 3, x: 0, y: 1)
        .shadow(color: .black.opacity(0.7), radius: 14, x: 0, y: 4)
        .frame(maxWidth: .infinity)
    }

    private func parallaxHeroCover(for release: Release) -> some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .named("releaseScroll")).minY
            let width = proxy.size.width
            let height = width

            // Détection du scroll vers le haut (swipe up) : minY < 0
            let scrollUp = max(0, -minY)
            // Étirement fluide si traction vers le bas (pull-down rubberband) : minY > 0
            let pullDown = max(0, minY)

            // Progression du swipe up étalée sur toute la hauteur de la jaquette
            let maxDistance = max(1.0, height * 1.0)
            let rawProgress = min(1.0, scrollUp / maxDistance)

            // Courbe progressive douce (puissance 1.6) :
            // La jaquette conserve sa netteté au début du scroll, puis s'adoucit très délicatement
            let easedProgress = pow(rawProgress, 1.6)

            // Floutage progressif : de 0 pt (net) à 30 pt (ambiance fluide et colorée)
            let blurRadius = easedProgress * 30.0

            // Effet parallaxe : la jaquette monte 2 fois moins vite que le défilement (désactivé
            // avec Réduire les animations : elle défile alors avec le contenu).
            let parallaxOffset = reduceMotion ? 0 : scrollUp * 0.5

            ZStack {
                // Fond teinté de la couleur moyenne pour éviter tout blanchiment en arrière-plan
                infoBackgroundColor

                AsyncCoverImage(
                    url: release.primaryImageURL ?? initialCoverURL,
                    cornerRadius: 0,
                    showsBorder: false,
                    onAverageColorLoaded: { color in
                        ReleaseColorCache.shared.register(color: color, forReleaseId: releaseId, url: release.primaryImageURL)
                        withAnimation(.easeInOut(duration: 0.35)) {
                            viewModel.averageColor = color
                        }
                    }
                )
                .aspectRatio(1, contentMode: .fill)
                .frame(width: width, height: height + pullDown, alignment: .top)
                .scaleEffect(1.0 + easedProgress * 0.10) // Empêche les bords blanchis par le flou
                .blur(radius: blurRadius)
                .clipped()
            }
            .frame(width: width, height: height + pullDown, alignment: .top)
            .clipped()
            .offset(y: -pullDown + parallaxOffset)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let images = release.images, !images.isEmpty else { return }
            imageViewerRequest = ImageViewerRequest(startIndex: 0)
        }
        .accessibilityLabel("Pochette de l'album")
        .accessibilityHint("Voir en plein écran")
        .accessibilityAddTraits(.isButton)
    }

}

#Preview {
    NavigationStack {
        ReleaseDetailView(releaseId: 249504)
    }
}
