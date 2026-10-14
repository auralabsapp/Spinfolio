import SwiftUI

struct ArtistDetailView: View {
    let artistId: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel = ArtistDetailViewModel()
    private var networkMonitor = NetworkMonitor.shared
    @State private var scrollOffsetY: CGFloat = 0

    /// Disparition très douce et progressive du nom lors du swipe up — mêmes constantes que
    /// `ReleaseDetailView.titleOpacity`, pour un ressenti identique entre les deux écrans.
    private var titleOpacity: Double {
        let scrollUp = Double(max(0, scrollOffsetY))
        let fadeDistance: Double = 200.0
        let progress = min(1.0, scrollUp / fadeDistance)
        return max(0.0, (1.0 + cos(.pi * progress)) / 2.0)
    }

    /// Fond teinté d'après la couleur moyenne de la photo, comme sur la fiche album
    /// (`ReleaseDetailView.infoBackgroundColor`) ; fond système tant qu'elle n'est pas connue.
    private var infoBackgroundColor: Color {
        if let averageColor = viewModel.averageColor {
            return averageColor.infoBackgroundColor(for: colorScheme)
        }
        return Color(uiColor: .systemBackground)
    }

    /// Fondu entre la photo et la zone d'informations : mêmes paliers sur courbe cosinus que
    /// `ReleaseDetailView.heroToInfoGradient`, vers la même teinte de fond.
    private var heroToInfoGradient: LinearGradient {
        let stopCount = 24
        let stops: [Gradient.Stop] = (0...stopCount).map { step in
            let location = Double(step) / Double(stopCount)
            let eased = (1.0 - cos(.pi * location)) / 2.0
            return .init(color: infoBackgroundColor.opacity(eased), location: location)
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    private var toolbarIconColor: Color {
        colorScheme == .dark ? .white : .black
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
                            .foregroundStyle(toolbarIconColor)
                    }
                    .accessibilityLabel("Retour")
                }

                // Mêmes emplacement et style que sur la fiche album ; liens vers la page Apple
                // Music de l'artiste (le lien Discogs est sous la section « Discographie Discogs »).
                if let url = viewModel.appleMusicURL {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.body.weight(.medium))
                                .foregroundStyle(toolbarIconColor)
                        }
                        .accessibilityLabel("Partager l'artiste")

                        Button {
                            openURL(url)
                        } label: {
                            Image(systemName: "music.note")
                                .font(.body.weight(.medium))
                                .foregroundStyle(toolbarIconColor)
                        }
                        .accessibilityLabel("Ouvrir dans Apple Music")
                    }
                }
            }
            .task { await viewModel.load(artistId: artistId) }
            // Retour depuis les Réglages iOS après avoir accordé l'accès à Apple Music.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await viewModel.refreshAfterReturningToForeground() }
            }
            .onAppear {
                TabNavigationCoordinator.shared.registerTopDestination(.artist(artistId))
            }
            .onDisappear {
                TabNavigationCoordinator.shared.unregisterTopDestination(.artist(artistId))
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            artistDetailSkeleton
                .transition(.opacity)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView(
                "Impossible de charger cet artiste",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if viewModel.artistName != nil {
            ScrollView {
                VStack(spacing: 0) {
                    parallaxHeroCover(artworkURLString: viewModel.artworkURL?.absoluteString)

                    VStack(spacing: 0) {
                        // Nom Apple Music remonté sur la photo, centré, disparaissant très
                        // progressivement lors du swipe up — même police/ombres que le titre
                        // d'album de `ReleaseDetailView`. Grisé (`redacted`) tant que l'artiste
                        // Apple Music n'est pas identifié, pour ne pas changer de nom sous les yeux.
                        Text(viewModel.title)
                            .redacted(reason: viewModel.isResolvingAppleMusicArtist ? .placeholder : [])
                            .font(.title.bold())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .shadow(color: .black.opacity(0.9), radius: 3, x: 0, y: 1)
                            .shadow(color: .black.opacity(0.7), radius: 14, x: 0, y: 4)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                            .padding(.bottom, 32)
                            .opacity(titleOpacity)
                            .background(heroToInfoGradient)

                        VStack(alignment: .leading, spacing: 20) {
                            if !networkMonitor.isConnected {
                                if viewModel.isLibrarySnapshotStale {
                                    // Même bandeau, mêmes conditions que la Collection (cache de
                                    // plus de 6 heures) : la possession et le nom affichés ici en
                                    // proviennent.
                                    OfflineBannerView(
                                        lastSyncDate: OfflineDownloadManager.shared.lastSyncDate,
                                        itemCount: OfflineDownloadManager.shared.offlineItemCount
                                    )
                                } else if viewModel.hasIncompleteAppleMusicContent && viewModel.appleMusicAccess != .denied {
                                    // Cache récent, mais il manque des éléments Apple Music : seulement
                                    // s'il manque quelque chose (une page déjà complète, chargée avant
                                    // la coupure, n'a rien à signaler).
                                    OfflineBannerView(customMessage: String(localized: "La photo et la biographie s'afficheront au retour du réseau."))
                                }
                            }

                            if viewModel.ownedCount > 0 || viewModel.wantlistCount > 0 {
                                ownershipSummaryRow
                            }

                            if viewModel.appleMusicAccess == .denied {
                                appleMusicAccessCard
                            } else {
                                if let biography = viewModel.biography, !biography.isEmpty {
                                    Text(biography)
                                        .font(.body)
                                        .transition(.opacity)
                                }
                            }

                            // Indépendante d'Apple Music : affichée même si son accès est refusé.
                            discogsDiscographySection
                        }
                        .padding()
                        .background(infoBackgroundColor)
                        // La biographie arrive après l'affichage de la page : on anime son
                        // insertion plutôt que de faire sauter le contenu d'un coup.
                        .animation(.easeInOut(duration: 0.3), value: viewModel.biography)
                    }
                    .padding(.top, -130)
                }
            }
            .coordinateSpace(name: "artistScroll")
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { _, newValue in
                scrollOffsetY = newValue
            }
            .ignoresSafeArea(edges: .all)
            .transition(.opacity)
        }
    }

    /// Gabarit neutre affiché pendant le chargement, à la place d'une icône de chargement :
    /// photo en plein bord (comme la vraie photo héro, pas de nom superposé tant qu'on ne l'a
    /// pas), un paragraphe neutre (biographie) puis la section "Discographie Discogs" (toujours
    /// présente), avec des blocs animés (voir `SkeletonBlock`).
    private var artistDetailSkeleton: some View {
        ScrollView {
            VStack(spacing: 0) {
                SkeletonBlock(cornerRadius: 0)
                    .aspectRatio(1, contentMode: .fit)
                    .padding(.bottom, 24)

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBlock(height: 14)
                        SkeletonBlock(height: 14)
                        SkeletonBlock(width: 200, height: 14)
                    }

                    SkeletonSection(titleWidth: 150, contentHeight: 220)
                }
                .padding()
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollDisabled(true)
    }

    /// Hauteur maximale de l'en-tête. Sans plafond, la photo carrée en pleine largeur dépassait
    /// 1 000 pt de haut sur iPad ; sur iPhone (largeur < 480 pt), elle reste carrée.
    private static let maxHeroHeight: CGFloat = 480

    /// Photo d'artiste (Apple Music uniquement) en en-tête, carrée sur iPhone et plafonnée en
    /// hauteur sur iPad, avec effet parallaxe (défile 2x moins vite que le contenu) et flou
    /// progressif lors du swipe up — même mécanique que `ReleaseDetailView.parallaxHeroCover`,
    /// adaptée à une simple photo plutôt qu'une jaquette avec galerie.
    private func parallaxHeroCover(artworkURLString: String?) -> some View {
        // Conteneur carré limité en hauteur puis étendu à toute la largeur : la photo occupe
        // toute la largeur sur une hauteur = min(largeur, plafond), recadrée au centre.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxHeight: Self.maxHeroHeight)
            .frame(maxWidth: .infinity)
            .overlay { parallaxHeroContent(artworkURLString: artworkURLString) }
    }

    private func parallaxHeroContent(artworkURLString: String?) -> some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .named("artistScroll")).minY
            let width = proxy.size.width
            let height = proxy.size.height

            let scrollUp = max(0, -minY)
            let pullDown = max(0, minY)

            let maxDistance = max(1.0, height)
            let rawProgress = min(1.0, scrollUp / maxDistance)
            let easedProgress = pow(rawProgress, 1.6)
            let blurRadius = easedProgress * 30.0
            let parallaxOffset = scrollUp * 0.5

            ZStack {
                Color(uiColor: .secondarySystemBackground)

                if let artworkURLString {
                    AsyncCoverImage(
                        url: artworkURLString,
                        cornerRadius: 0,
                        showsBorder: false,
                        onAverageColorLoaded: { color in
                            withAnimation(.easeInOut(duration: 0.35)) {
                                viewModel.averageColor = color
                            }
                        }
                    )
                        .aspectRatio(1, contentMode: .fill)
                        // Recadrage centré (et non en haut comme pour une jaquette) : le visage
                        // d'une photo d'artiste est rarement collé au bord supérieur.
                        .frame(width: width, height: height + pullDown, alignment: .center)
                        .scaleEffect(1.0 + easedProgress * 0.10)
                        .blur(radius: blurRadius)
                        .clipped()
                        // Fondu depuis le fond d'attente quand la photo Apple Music (déjà
                        // préchargée, voir `ArtistDetailViewModel.load`) est prête.
                        .transition(.opacity)
                } else if viewModel.isLoadingArtwork {
                    ProgressView()
                } else {
                    // Aucune photo Apple Music pour cet artiste : pas de repli sur Discogs.
                    Image(systemName: "music.mic")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(Color.appTertiaryText)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: artworkURLString)
            .frame(width: width, height: height + pullDown, alignment: .top)
            .clipped()
            .offset(y: -pullDown + parallaxOffset)
        }
    }

    /// Sélecteur de section de la discographie Discogs : segmenté (pleine largeur) si ses
    /// libellés tiennent en entier — `ViewThatFits` compare la taille idéale de chaque option à
    /// la largeur disponible ; sinon (petit iPhone, grandes tailles de texte), des pastilles qui
    /// défilent horizontalement, plutôt que des segments aux libellés tronqués.
    private func sectionPicker<Option: Hashable & Identifiable>(
        selection: Binding<Option>,
        options: [Option],
        title: @escaping (Option) -> String
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            Picker("Section", selection: selection) {
                ForEach(options) { option in
                    Text(title(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options) { option in
                        sectionChip(title: title(option), isSelected: selection.wrappedValue == option) {
                            selection.wrappedValue = option
                        }
                    }
                }
            }
        }
    }

    private func sectionChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.spinlogPink : Color.primary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Ligne de la discographie : pochette, titre, ligne secondaire (année…) et pastilles de
    /// possession.
    private func workRow<Subtitle: View>(
        coverURL: String?,
        title: String,
        isOwned: Bool,
        isInWantlist: Bool,
        @ViewBuilder subtitle: () -> Subtitle
    ) -> some View {
        HStack(spacing: 12) {
            AsyncCoverImage(url: coverURL, cornerRadius: 6, targetSize: 56)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    subtitle()
                }
                .font(.caption)
                .foregroundStyle(Color.appSecondaryText)
            }

            Spacer(minLength: 8)

            statusBadges(isOwned: isOwned, isInWantlist: isInWantlist)
        }
        .padding(.vertical, 6)
        // Toute la ligne réagit au toucher : avec `.buttonStyle(.plain)`, seules les zones
        // dessinées (pochette, textes, pastilles) le faisaient, pas l'espace vide du `Spacer`.
        .contentShape(Rectangle())
        // Lue comme un seul élément par VoiceOver (titre, année, statut).
        .accessibilityElement(children: .combine)
    }

    /// Pastilles affichées uniquement quand il y a quelque chose à signaler : une pastille
    /// « Non possédé » sur chaque autre ligne alourdissait la liste sans rien apprendre.
    @ViewBuilder
    private func statusBadges(isOwned: Bool, isInWantlist: Bool) -> some View {
        if isOwned || isInWantlist {
            VStack(alignment: .trailing, spacing: 4) {
                if isOwned {
                    StatusBadgeView(status: .owned)
                }
                if isInWantlist {
                    StatusBadgeView(status: .inWantlist)
                }
            }
        }
    }

    // MARK: - Discographie Discogs

    /// Œuvres principales de l'artiste selon Discogs (masters et releases isolées), seule
    /// discographie de la page. Une œuvre possédée ou en wantlist ouvre la fiche de ton
    /// exemplaire ; un master non possédé, sa fiche master ; une release isolée non possédée
    /// reste purement informative (ni lien, ni chevron).
    private var discogsDiscographySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Discographie Discogs", icon: "opticaldisc")

            // Juste sous le titre, pour rester visible quelle que soit la section affichée.
            discogsClassificationStatus

            switch viewModel.discogsDiscographyState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            case .unavailable where !networkMonitor.isConnected:
                // Pas de bouton « Réessayer » : la section se recharge seule au retour du réseau.
                Text("Disponible au retour du réseau.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            case .unavailable:
                VStack(spacing: 10) {
                    Text("Discographie Discogs indisponible pour le moment.")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                        .multilineTextAlignment(.center)
                    Button("Réessayer") {
                        Task { await viewModel.retryDiscogsDiscography() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            case .loaded(let isLoadingMore, let isTruncated):
                if viewModel.discogsWorks.isEmpty && !isLoadingMore {
                    Text("Aucun album principal de cet artiste sur Discogs.")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                        .padding(.vertical, 8)
                } else {
                    sectionPicker(
                        selection: $viewModel.selectedDiscogsFilter,
                        options: viewModel.discogsFilterOptions,
                        title: viewModel.title(for:)
                    )

                    let entries = viewModel.discogsEntries()
                    if entries.isEmpty {
                        // Section vide pour l'instant si le classement est encore en cours.
                        if !viewModel.isSortingDiscogsWorks {
                            Text("Aucune œuvre dans cette section.")
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                                .padding(.vertical, 8)
                        }
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(entries) { entry in
                                if let destination = entry.destination {
                                    NavigationLink(value: destination) {
                                        discogsRow(for: entry)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    discogsRow(for: entry)
                                }
                            }
                        }
                    }

                    if isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
                if isTruncated {
                    Text("Discographie partielle : seules les sorties les plus récentes ont pu être chargées.")
                        .font(.caption2)
                        .foregroundStyle(Color.appSecondaryText)
                }
                // Mention exigée par les CGU de l'API Discogs à côté des données qui en
                // proviennent (titres, années, pochettes de cette section).
                if !viewModel.discogsWorks.isEmpty, let url = viewModel.discogsArtistURL {
                    DiscogsAttributionLink(url: url)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
            }
        }
    }

    /// Progression du classement des œuvres en sections (une requête par master encore jamais
    /// classé, au rythme de l'API Discogs ; mémorisé ensuite), ou œuvres restées non classées
    /// après un classement interrompu, avec nouvel essai.
    @ViewBuilder
    private var discogsClassificationStatus: some View {
        if let progress = viewModel.discogsClassificationProgress {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Classement des œuvres : \(progress.done)/\(progress.total)")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .monospacedDigit()
            }
        } else if !viewModel.isSortingDiscogsWorks && viewModel.pendingDiscogsCount > 0 {
            HStack(spacing: 8) {
                Text("\(viewModel.pendingDiscogsCount) œuvres non classées")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                // Hors ligne, le classement reprend seul au retour du réseau.
                if networkMonitor.isConnected {
                    Button("Réessayer") {
                        Task { await viewModel.retryDiscogsClassification() }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private func discogsRow(for entry: ArtistDetailViewModel.DiscogsWorkEntry) -> some View {
        workRow(
            coverURL: entry.work.thumb,
            title: entry.work.title,
            isOwned: entry.isOwned,
            isInWantlist: entry.isInWantlist
        ) {
            if let year = entry.work.year, year > 0 {
                Text(verbatim: String(year))
            }
        }
    }

    /// Résumé "X possédés / Y en wantlist" sous la photo — albums distincts de cet artiste
    /// (voir `ArtistDetailViewModel.ownedCount`/`wantlistCount`),
    /// masqué entièrement si l'utilisateur n'a aucun lien avec cet artiste dans sa collection.
    private var ownershipSummaryRow: some View {
        HStack(spacing: 24) {
            // Deux chaînes distinctes plutôt qu'une variante de pluriel du catalogue : le nombre
            // est affiché à part, en grand, et le catalogue refuse une variante de pluriel qui ne
            // contient pas le nombre (Apple recommande alors justement une chaîne pour « un » et
            // une pour « plusieurs »). Ces compteurs ne s'affichent qu'à partir de 1, donc
            // `count == 1` suffit à choisir la bonne forme en français comme en anglais.
            if viewModel.ownedCount > 0 {
                ownershipSummaryStat(
                    count: viewModel.ownedCount,
                    label: viewModel.ownedCount == 1 ? String(localized: "album possédé") : String(localized: "albums possédés")
                )
            }
            if viewModel.ownedCount > 0 && viewModel.wantlistCount > 0 {
                Divider().frame(height: 28)
            }
            if viewModel.wantlistCount > 0 {
                ownershipSummaryStat(
                    count: viewModel.wantlistCount,
                    label: viewModel.wantlistCount == 1 ? String(localized: "album en wantlist") : String(localized: "albums en wantlist")
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func ownershipSummaryStat(count: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title2.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.appSecondaryText)
        }
    }

    /// Remplace la biographie quand l'accès à Apple Music est refusé : sans cette
    /// explication, la page restait quasi vide sans dire pourquoi. Seuls les Réglages iOS
    /// permettent de revenir sur un refus (l'invite système ne se représente plus) ; la page se
    /// complète d'elle-même au retour dans l'app (voir `refreshAfterReturningToForeground`).
    private var appleMusicAccessCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.largeTitle)
                .foregroundStyle(Color.spinlogPink)
            Text("Accès à Apple Music désactivé")
                .font(.headline)
            Text("La photo et la biographie de l'artiste viennent d'Apple Music. Autorise \(AppInfo.name) à y accéder dans les Réglages.")
                .font(.subheadline)
                .foregroundStyle(Color.appSecondaryText)
                .multilineTextAlignment(.center)
            Button("Ouvrir Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.spinlogPink)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .appleMusicGroupedCard()
    }
}
