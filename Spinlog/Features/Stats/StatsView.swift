import SwiftUI
import Charts
import Kingfisher

struct YearReleasesSheetData: Identifiable {
    var id: String { "\(type)_\(year)" }
    let year: Int
    let items: [CollectionItem]
    var type: String = "additions" // "additions" ou "originalYears"
    /// Titre complet de la feuille (« Ajoutés en 2021 », « Sortis dans les années 1990 »…) :
    /// construit d'un bloc plutôt que par préfixe + année, l'ordre des mots variant selon la langue.
    var title: String
}

struct GenreReleasesSheetData: Identifiable {
    var id: String { genre }
    let genre: String
    let items: [CollectionItem]
}

/// Générique pour "Répartition par support" : sert aussi bien à la part large (Vinyles/CD/...)
/// qu'au détail par taille de vinyle (12"/10"/7"), les deux n'étant qu'une liste titrée.
struct MediaFormatReleasesSheetData: Identifiable {
    var id: String { title }
    let title: String
    let items: [CollectionItem]
}

struct ArtistReleasesSheetData: Identifiable {
    var id: String { artist }
    let artist: String
    let items: [CollectionItem]

    /// Artistes Discogs derrière `artist` : tous les disques du groupe portent les mêmes noms
    /// (voir `StatsViewModel.items(forArtist:)`), le premier suffit.
    var artists: [ReleaseArtist] { items.first?.basicInformation.artists ?? [] }
}

enum PodiumPeriod: String, CaseIterable, Identifiable {
    case yearly
    case monthly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yearly: return String(localized: "Cette année")
        case .monthly: return String(localized: "Ce mois-ci")
        }
    }
}

enum TopEntityKind: String, CaseIterable, Identifiable {
    case albums
    case artists

    var id: String { rawValue }

    var label: String {
        switch self {
        case .albums: return String(localized: "Albums")
        case .artists: return String(localized: "Artistes")
        }
    }
}

enum OriginalYearsGranularity: String, CaseIterable, Identifiable {
    case decade
    case year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .year: return String(localized: "Par année")
        case .decade: return String(localized: "Par décennie")
        }
    }
}

struct StatsView: View {
    /// Partagée entre les pochettes de `recentAdditionsSection` et son squelette, pour que ce
    /// dernier ne puisse pas diverger silencieusement de la taille réelle.
    static let recentAdditionCoverSize: CGFloat = 96

    @State var viewModel = StatsViewModel()
    @State var authManager = DiscogsAuthManager.shared
    @State var premiumStore = PremiumStore.shared
    @State var selectedAdditionsYear: String?
    @State var selectedOriginalYear: String?
    @State var selectedYearData: YearReleasesSheetData?
    @State var selectedGenreName: String?
    @State var selectedAngle: Double?
    @State var selectedGenreData: GenreReleasesSheetData?
    @State var selectedArtistData: ArtistReleasesSheetData?
    @State var selectedMediaFormatName: String?
    @State var selectedMediaFormatAngle: Double?
    @State var selectedMediaFormatData: MediaFormatReleasesSheetData?
    @State var selectedLabelName: String?
    @State var selectedLabelAngle: Double?
    @State var podiumPeriod: PodiumPeriod = .yearly
    @State var topEntityKind: TopEntityKind = .albums
    @State var networkMonitor = NetworkMonitor.shared
    @State var originalYearsGranularity: OriginalYearsGranularity = .decade

    let maxVisibleBars = 10

    var maxAdditionsCount: Int {
        viewModel.additionsPerYear.map(\.count).max() ?? 0
    }

    /// Répartition des années originales à afficher, selon la granularité choisie : les deux
    /// partagent le même type `(year: Int, count: Int)` pour que le graphique et sa logique de
    /// sélection restent communs (`year` porte alors le début de décennie en mode décennie).
    var currentOriginalYearsDistribution: [(year: Int, count: Int)] {
        switch originalYearsGranularity {
        case .year:
            return viewModel.originalYearsDistribution
        case .decade:
            return viewModel.originalYearsDistributionByDecade.map { (year: $0.decade, count: $0.count) }
        }
    }

    var maxOriginalYearsCount: Int {
        currentOriginalYearsDistribution.map(\.count).max() ?? 0
    }

    var body: some View {
        content
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Statistiques")
            .searchDestinations()
            .task(id: authManager.isAuthenticated) {
                if authManager.isAuthenticated {
                    await viewModel.loadOverview()
                }
            }
            // Sans ça, un point d'historique de valeur ou un champ "prix d'achat" mis à jour par
            // `CloudSyncEngine` depuis un autre appareil est bien écrit en local, mais le total
            // investi continue d'afficher l'ancienne valeur tant que cet écran reste ouvert.
            // `valueHistorySection` est masquée pour l'instant (voir le corps ci-dessous), mais le
            // reste de la mécanique (enregistrement à chaque visite de cet écran, synchro iCloud
            // des points déjà enregistrés) reste actif pour un usage futur — ce n'est pas pour
            // autant une vraie tâche d'arrière-plan : aucun nouveau point n'est créé si l'onglet
            // Stats n'est jamais ouvert.
            .onReceive(NotificationCenter.default.publisher(for: .collectionSnapshotsChanged)) { _ in
                viewModel.refreshValueHistoryFromLocalStore()
            }
            .onReceive(NotificationCenter.default.publisher(for: .collectionPreferencesChanged)) { _ in
                Task { await viewModel.computeTotalInvestedIfNeeded() }
            }
    }

    @ViewBuilder
    var content: some View {
        if !authManager.isAuthenticated {
            LoginPromptView(message: String(localized: "Connecte-toi à Discogs pour voir tes statistiques."))
        } else {
            // Le squelette de chargement et le contenu réel partagent le même
            // `ScrollViewReader`/`ScrollView` (seul le contenu du `VStack` change selon
            // `isLoadingOverview`) : les reconstruire séparément détruisait et recréait toute la
            // hiérarchie de défilement à chaque bascule, ce qui faisait disparaître puis
            // réapparaître le grand titre de navigation au moment où le squelette laissait place
            // au contenu réel.
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if viewModel.isLoadingOverview {
                            statsSkeletonContent
                        } else {
                        // Les compteurs et la cote de marché nécessitent le réseau et affichent
                        // déjà leur propre état indisponible ("–", "Estimation indisponible") :
                        // on ne bloque donc plus tout l'écran derrière `viewModel.errorMessage`,
                        // alors que la plupart des autres sections viennent du cache local et
                        // fonctionnent très bien hors ligne.
                        if !networkMonitor.isConnected {
                            OfflineBannerView(customMessage: String(localized: "Certaines statistiques (compteurs, cote de marché) nécessitent une connexion réseau"))
                        }

                        countersRow
                        recentAdditionsSection
                        additionsHistogramSection(scrollProxy: scrollProxy)
                        originalYearsHistogramSection(scrollProxy: scrollProxy)
                        topArtistsSection
                        genreDistributionSection
                        mediaFormatDistributionSection
                        labelDistributionSection
                        valuationSection
                        // `valueHistorySection` volontairement masquée pour l'instant (pas encore
                        // jugée pertinente) : la mécanique de suivi/synchro continue de tourner
                        // en arrière-plan (voir `recordCollectionSnapshotIfNeeded`), prête à être
                        // réaffichée plus tard sans rien reconstruire.
                        investedVsValueSection
                        listeningStatsSection
                        }
                    }
                    .padding()
                    // Marge inférieure augmentée quand la bottom sheet est ouverte pour garantir que
                    // le titre du graphique puisse défiler librement jusqu'au bord supérieur de l'écran.
                    .padding(.bottom, (selectedYearData != nil || selectedGenreData != nil || selectedArtistData != nil || selectedMediaFormatData != nil) ? 420 : 0)
                }
                .sheet(item: $selectedYearData, onDismiss: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedAdditionsYear = nil
                        selectedOriginalYear = nil
                    }
                }) { data in
                    YearReleasesSheetView(data: data)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                }
                .sheet(item: $selectedGenreData, onDismiss: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedGenreName = nil
                    }
                }) { data in
                    GenreReleasesSheetView(data: data)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                }
                .sheet(item: $selectedArtistData) { data in
                    ArtistReleasesSheetView(data: data)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                }
                .sheet(item: $selectedMediaFormatData) { data in
                    MediaFormatReleasesSheetView(data: data)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                }
            }
        }
    }

    /// Contenu du gabarit neutre affiché pendant le chargement initial, à la place d'une icône
    /// de chargement : la structure de la page étant connue à l'avance, chaque section garde son
    /// vrai titre (`SectionEyebrow`, comme dans la page réelle) au-dessus d'un bloc de contenu
    /// neutre (voir `SkeletonBlock`), plutôt que de tout griser. Pas de `ScrollView` propre ici :
    /// ce contenu s'insère directement dans le `VStack` partagé avec le contenu réel (voir le
    /// commentaire dans `content`), pour ne jamais reconstruire la hiérarchie de défilement.
    @ViewBuilder
    var statsSkeletonContent: some View {
        HStack(spacing: 12) {
            statsCounterSkeletonCard(icon: "square.stack.fill")
            statsCounterSkeletonCard(icon: "heart.fill")
            statsCounterSkeletonCard(icon: "person.2.fill")
        }
        .fixedSize(horizontal: false, vertical: true)

        statsSkeletonSection(title: "Derniers ajouts", icon: "clock.fill", contentHeight: 100)
        statsSkeletonSection(title: "Exemplaires ajoutés par année", icon: "chart.bar.xaxis", contentHeight: 180)
        statsSkeletonSection(title: "Sorties originales", icon: "calendar", contentHeight: 180)
        statsSkeletonSection(title: "Classement des artistes", icon: "person.2.fill", contentHeight: 220)
        statsSkeletonSection(title: "Répartition par genre", icon: "chart.pie.fill", contentHeight: 220)
        statsSkeletonSection(title: "Répartition par support", icon: "square.stack.3d.up.fill", contentHeight: 220)
        statsSkeletonSection(title: "Répartition par label", icon: "tag.fill", contentHeight: 220)
        statsSkeletonSection(title: "Estimation de la collection", icon: "banknote.fill", contentHeight: 140)
        statsSkeletonSection(title: "Investi vs Cote actuelle", icon: "arrow.left.arrow.right.circle.fill", contentHeight: 130)
        statsSkeletonSection(title: "Tops & Palmarès", icon: "waveform", contentHeight: 240)
    }

    /// Même habillage que `StatCounterCard` (icône, carte groupée), avec un bloc neutre à la
    /// place du nombre et de l'unité tant qu'ils ne sont pas connus : l'icône réelle identifie
    /// déjà la tuile (Collection/Wantlist/Artistes) dès le squelette.
    func statsCounterSkeletonCard(icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.spinlogPink)
                Spacer()
            }

            // Hauteurs alignées sur les hauteurs de ligne réelles (`.title.bold()` pour la
            // valeur, `.caption` pour le sous-titre dans `StatCounterCard.cardContent`) : les
            // 24/11pt précédents, trop courts, faisaient grandir toute la rangée au chargement du
            // vrai texte et poussaient "Derniers ajouts" (et tout ce qui suit) vers le bas.
            SkeletonBlock(cornerRadius: 6, width: 36, height: 34)
            SkeletonBlock(cornerRadius: 4, width: 50, height: 16)
        }
        // Même `maxHeight: .infinity` que `StatCounterCard.cardContent` : les 3 cartes du
        // squelette ont ici un contenu identique (donc déjà la même hauteur intrinsèque), mais
        // autant rester cohérent avec le vrai contenu plutôt que de dépendre de cette coïncidence.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .appleMusicGroupedCard()
    }

    func statsSkeletonSection(title: LocalizedStringKey, icon: String, contentHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: title, icon: icon)
            SkeletonBlock(cornerRadius: 14, height: contentHeight)
        }
    }

    var countersRow: some View {
        HStack(spacing: 12) {
            StatCounterCard(
                title: "Collection",
                value: viewModel.totalCollectionCount.map(String.init) ?? "–",
                subtitle: viewModel.totalCollectionCount.map { $0 == 1 ? String(localized: "album") : String(localized: "albums") },
                systemImage: "square.stack.fill",
                tint: Color.spinlogPink
            ) {
                TabNavigationCoordinator.shared.openCollectionAtTop()
            }
            StatCounterCard(
                title: "Wantlist",
                value: viewModel.totalWantlistCount.map(String.init) ?? "–",
                subtitle: viewModel.totalWantlistCount.map { $0 == 1 ? String(localized: "album") : String(localized: "albums") },
                systemImage: "heart.fill",
                tint: Color.spinlogPink
            ) {
                TabNavigationCoordinator.shared.openWantlistAtTop()
            }
            StatCounterCard(
                title: "Artistes",
                value: viewModel.uniqueArtistsCount.map(String.init) ?? "–",
                subtitle: viewModel.uniqueArtistsCount.map { $0 == 1 ? String(localized: "artiste") : String(localized: "artistes") },
                systemImage: "person.2.fill",
                tint: Color.spinlogPink
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    var recentAdditionsSection: some View {
        if viewModel.isLoadingCounters && viewModel.recentAdditions.isEmpty {
            // Seule section encore dépendante du réseau une fois le reste de l'écran affiché
            // depuis le cache (voir `isLoadingCounters`) : gabarit propre à cette section (plutôt
            // que le bloc neutre générique de `statsSkeletonContent`) pour réserver la même place
            // que le contenu réel — une pochette carrée puis 2 lignes de texte par carte.
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(title: "Derniers ajouts", icon: "clock.fill")
                // `ScrollView` au même titre que le contenu réel juste en dessous : sans elle, ces
                // 4 cartes de 96pt (soit 420pt avec les espacements) dépassaient la largeur de
                // l'écran et élargissaient tout le squelette, qui "rétrécissait" ensuite d'un coup
                // au chargement du vrai contenu — lequel ne pousse jamais la largeur de la page
                // puisqu'il est, lui, dans un `ScrollView` horizontal.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 4) {
                                SkeletonBlock(cornerRadius: 8, width: Self.recentAdditionCoverSize, height: Self.recentAdditionCoverSize)
                                // Hauteurs alignées sur les hauteurs de ligne réelles
                                // (`.caption.weight(.semibold)` puis `.caption2` dans le vrai
                                // contenu ci-dessous) : avec les 11/9pt précédents, trop courts,
                                // la section grandissait légèrement au chargement du vrai texte et
                                // poussait tout ce qui suit vers le bas.
                                SkeletonBlock(width: 70, height: 15)
                                SkeletonBlock(width: 50, height: 12)
                            }
                            .frame(width: Self.recentAdditionCoverSize)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        } else if !viewModel.recentAdditions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(title: "Derniers ajouts", icon: "clock.fill")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.recentAdditions) { item in
                            NavigationLink(value: SearchDestination.release(item.releaseId, coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    AsyncCoverImage(url: item.basicInformation.coverImage ?? item.basicInformation.thumb, cornerRadius: 8, targetSize: Self.recentAdditionCoverSize)
                                        .frame(width: Self.recentAdditionCoverSize, height: Self.recentAdditionCoverSize)
                                        // Micro-bordure pour l'épaisseur carton, comme les pochettes
                                        // de la Collection et de la Wantlist.
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                                        )
                                        // Ombre de contact (très proche) puis ombre d'ambiance
                                        // flottante (large et douce), même recette que les autres
                                        // pochettes de l'app.
                                        .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 3)
                                        .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)
                                    Text(item.basicInformation.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                    Text(item.basicInformation.artistNames)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .foregroundStyle(Color.appSecondaryText)
                                }
                                .frame(width: Self.recentAdditionCoverSize)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
    }
}
