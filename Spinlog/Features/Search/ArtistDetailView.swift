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
                // Music de l'artiste (aucun lien Discogs sur cette page).
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
            .task(id: viewModel.selectedSection) {
                await viewModel.loadSectionIfNeeded(viewModel.selectedSection)
            }
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
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            // Seulement s'il manque quelque chose : hors ligne avec une page déjà
                            // complète (chargée avant la coupure), il n'y a rien à signaler.
                            if !networkMonitor.isConnected && viewModel.hasIncompleteAppleMusicContent
                                && viewModel.appleMusicAccess != .denied {
                                OfflineBannerView(customMessage: String(localized: "La photo, la biographie et la discographie s'afficheront au retour du réseau."))
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

                                discographySection
                            }
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
        }
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

    /// Discographie entièrement issue d'Apple Music (voir `AppleMusicArtistArtworkService`), qui
    /// distingue nativement albums studio, singles/EP, lives et compilations. Le statut
    /// Possédé/Wantlist est calculé par rapprochement de titre avec la collection et la wantlist
    /// locales de l'utilisateur (voir `ArtistDetailViewModel.entries(for:)`).
    @ViewBuilder
    private var discographySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Discographie", icon: "square.stack")

            sectionSelector

            switch viewModel.visibleSectionState {
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
                    Text("Discographie indisponible sur Apple Music pour le moment.")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                        .multilineTextAlignment(.center)
                    Button("Réessayer") {
                        Task { await viewModel.retrySelectedSection() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            case .loaded(let albums) where albums.isEmpty:
                Text("Aucun résultat Apple Music pour cette section.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .padding(.vertical, 8)
            case .loaded(let albums):
                VStack(spacing: 0) {
                    ForEach(viewModel.entries(for: albums)) { entry in
                        if let destination = entry.destination {
                            NavigationLink(value: destination) {
                                discographyRow(for: entry)
                            }
                            .buttonStyle(.plain)
                        } else {
                            discographyRow(for: entry)
                        }
                    }
                }
            }
        }
    }

    /// Sélecteur segmenté (pleine largeur) si ses libellés tiennent en entier — `ViewThatFits`
    /// compare la taille idéale de chaque option à la largeur disponible ; sinon (petit iPhone,
    /// grandes tailles de texte), des pastilles qui défilent horizontalement, plutôt que des
    /// segments aux libellés tronqués (« Singles & … », « Compil… »).
    private var sectionSelector: some View {
        ViewThatFits(in: .horizontal) {
            Picker("Section", selection: $viewModel.selectedSection) {
                ForEach(DiscographySection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DiscographySection.allCases) { section in
                        sectionChip(for: section)
                    }
                }
            }
        }
    }

    private func sectionChip(for section: DiscographySection) -> some View {
        let isSelected = viewModel.selectedSection == section
        return Button {
            viewModel.selectedSection = section
        } label: {
            Text(section.title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.spinlogPink : Color.primary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func discographyRow(for entry: ArtistDetailViewModel.DiscographyEntry) -> some View {
        let group = entry.group
        return HStack(spacing: 12) {
            AsyncCoverImage(url: group.representative.artworkURL?.absoluteString, cornerRadius: 6, targetSize: 56)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.representative.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                // Année de la sortie originale, et nombre d'éditions regroupées sur cette ligne
                // (Deluxe, Explicit, remasterisée…) quand il y en a plusieurs.
                HStack(spacing: 4) {
                    if let year = group.originalYear {
                        Text(year)
                    }
                    if group.originalYear != nil && group.versionCount > 1 {
                        Text(verbatim: "·")
                    }
                    if group.versionCount > 1 {
                        Text("\(group.versionCount) versions")
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.appSecondaryText)
            }

            Spacer(minLength: 8)

            statusBadges(for: entry)
        }
        .padding(.vertical, 6)
    }

    /// Pastilles affichées uniquement quand il y a quelque chose à signaler : une pastille
    /// « Non possédé » sur chaque autre ligne alourdissait la liste sans rien apprendre.
    @ViewBuilder
    private func statusBadges(for entry: ArtistDetailViewModel.DiscographyEntry) -> some View {
        if entry.isOwned || entry.isInWantlist {
            VStack(alignment: .trailing, spacing: 4) {
                if entry.isOwned {
                    StatusBadgeView(status: .owned)
                }
                if entry.isInWantlist {
                    StatusBadgeView(status: .inWantlist)
                }
            }
        }
    }

    /// Résumé "X possédés / Y en wantlist" sous la photo — basé sur le même index titre/statut
    /// que les badges de la discographie (voir `ArtistDetailViewModel.ownedCount`/`wantlistCount`),
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

    /// Remplace biographie et discographie quand l'accès à Apple Music est refusé : sans cette
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
            Text("La photo, la biographie et la discographie de l'artiste viennent d'Apple Music. Autorise \(AppInfo.name) à y accéder dans les Réglages.")
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
