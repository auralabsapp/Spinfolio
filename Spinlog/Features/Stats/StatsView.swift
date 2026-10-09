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
}

private enum PodiumPeriod: String, CaseIterable, Identifiable {
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

private enum TopEntityKind: String, CaseIterable, Identifiable {
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

private enum OriginalYearsGranularity: String, CaseIterable, Identifiable {
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
    @State private var viewModel = StatsViewModel()
    @State private var authManager = DiscogsAuthManager.shared
    @State private var premiumStore = PremiumStore.shared
    @State private var selectedAdditionsYear: String?
    @State private var selectedOriginalYear: String?
    @State private var selectedYearData: YearReleasesSheetData?
    @State private var selectedGenreName: String?
    @State private var selectedAngle: Double?
    @State private var selectedGenreData: GenreReleasesSheetData?
    @State private var selectedArtistData: ArtistReleasesSheetData?
    @State private var selectedMediaFormatName: String?
    @State private var selectedMediaFormatAngle: Double?
    @State private var selectedMediaFormatData: MediaFormatReleasesSheetData?
    @State private var selectedLabelName: String?
    @State private var selectedLabelAngle: Double?
    @State private var podiumPeriod: PodiumPeriod = .yearly
    @State private var topEntityKind: TopEntityKind = .albums
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var originalYearsGranularity: OriginalYearsGranularity = .decade

    private let maxVisibleBars = 10

    private var maxAdditionsCount: Int {
        viewModel.additionsPerYear.map(\.count).max() ?? 0
    }

    /// Répartition des années originales à afficher, selon la granularité choisie : les deux
    /// partagent le même type `(year: Int, count: Int)` pour que le graphique et sa logique de
    /// sélection restent communs (`year` porte alors le début de décennie en mode décennie).
    private var currentOriginalYearsDistribution: [(year: Int, count: Int)] {
        switch originalYearsGranularity {
        case .year:
            return viewModel.originalYearsDistribution
        case .decade:
            return viewModel.originalYearsDistributionByDecade.map { (year: $0.decade, count: $0.count) }
        }
    }

    private var maxOriginalYearsCount: Int {
        currentOriginalYearsDistribution.map(\.count).max() ?? 0
    }

    var body: some View {
        content
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
    private var content: some View {
        if !authManager.isAuthenticated {
            LoginPromptView(message: String(localized: "Connecte-toi à Discogs pour voir tes statistiques."))
        } else if viewModel.isLoadingOverview {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
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

    private var countersRow: some View {
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
    private var recentAdditionsSection: some View {
        if !viewModel.recentAdditions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(title: "Derniers ajouts", icon: "clock.fill")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.recentAdditions) { item in
                            NavigationLink(value: SearchDestination.release(item.releaseId, coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    AsyncCoverImage(url: item.basicInformation.coverImage ?? item.basicInformation.thumb, cornerRadius: 8, targetSize: 96)
                                        .frame(width: 96, height: 96)
                                    Text(item.basicInformation.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                    Text(item.basicInformation.artistNames)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .foregroundStyle(Color.appSecondaryText)
                                }
                                .frame(width: 96)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
    }

    // MARK: - Graphique Camembert : Répartition par Genre

    @ViewBuilder
    private var topArtistsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow(title: "Classement des artistes", icon: "person.2.fill")

            if viewModel.topArtistsByCollectionCount.count > 10 {
                Text("Faire défiler verticalement pour afficher les autres artistes")
                    .font(.caption2)
                    .foregroundStyle(Color.appSecondaryText)
            }

            if viewModel.isLoadingHistogram && viewModel.topArtistsByCollectionCount.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .appleMusicGroupedCard()
            } else if viewModel.topArtistsByCollectionCount.isEmpty {
                Text("Pas encore assez de données.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .appleMusicGroupedCard()
            } else {
                let maxCount = viewModel.topArtistsByCollectionCount.map(\.count).max() ?? 1
                let rowHeight: CGFloat = 34
                let fullHeight = CGFloat(viewModel.topArtistsByCollectionCount.count) * rowHeight + 6
                let visibleHeight = min(fullHeight, rowHeight * 10 + 6)

                ScrollView(.vertical, showsIndicators: true) {
                    Chart(viewModel.topArtistsByCollectionCount, id: \.name) { entry in
                        BarMark(
                            x: .value("Albums", entry.count),
                            y: .value("Artiste", entry.name)
                        )
                        .foregroundStyle(topArtistBarGradient)
                        .cornerRadius(4)
                        .annotation(position: .trailing) {
                            Text("\(entry.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                    .chartXScale(domain: 0...(max(1, Int(Double(maxCount) * 1.2))))
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                    .frame(height: fullHeight)
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { location in
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let origin = geo[plotFrame].origin
                                    let relativeY = location.y - origin.y
                                    if let artistName: String = proxy.value(atY: relativeY) {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        let items = viewModel.items(forArtist: artistName)
                                        selectedArtistData = ArtistReleasesSheetData(artist: artistName, items: items)
                                    }
                                }
                                .accessibilityLabel("Sélectionner un artiste du classement")
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                }
                .frame(height: visibleHeight)
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .appleMusicGroupedCard()
            }
        }
    }

    private var genreDistributionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow(title: "Répartition par genre", icon: "chart.pie.fill")

            if viewModel.isLoadingHistogram && viewModel.genreDistribution.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .appleMusicGroupedCard()
            } else if viewModel.genreDistribution.isEmpty {
                Text("Pas encore assez de données de genre.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .appleMusicGroupedCard()
            } else {
                VStack(spacing: 0) {
                    ZStack {
                        Chart(Array(viewModel.genreDistribution.enumerated()), id: \.element.id) { index, entry in
                            let isSelected = selectedGenreName == entry.name
                            SectorMark(
                                angle: .value("Occurrences", entry.count),
                                innerRadius: .ratio(isSelected ? 0.58 : 0.62),
                                outerRadius: .ratio(isSelected ? 1.0 : 0.94),
                                angularInset: 1.5
                            )
                            .cornerRadius(5)
                            .foregroundStyle(genreColor(for: entry.name, index: index))
                            .opacity(selectedGenreName == nil || isSelected ? 1.0 : 0.35)
                        }
                        .chartAngleSelection(value: $selectedAngle)
                        .frame(height: 230)
                        .chartOverlay { proxy in
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture { location in
                                        handlePieChartTap(at: location, in: geo.size)
                                    }
                                    .accessibilityLabel("Sélectionner une part du graphique de répartition par genre")
                                    .accessibilityAddTraits(.isButton)
                            }
                        }

                        // Données dynamiques affichées au centre du camembert
                        VStack(spacing: 4) {
                            if let selected = viewModel.genreDistribution.first(where: { $0.name == selectedGenreName }) {
                                let color = genreColor(for: selected.name, index: viewModel.genreDistribution.firstIndex(where: { $0.name == selected.name }) ?? 0)

                                Text(selected.name)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)

                                Text((selected.percentage / 100).formatted(.percent.precision(.fractionLength(0))))
                                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                                    .foregroundStyle(color)

                                Text("\(selected.count) albums")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Color.appSecondaryText)

                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    let items = viewModel.items(forGenre: selected.name)
                                    selectedGenreData = GenreReleasesSheetData(genre: selected.name, items: items)
                                } label: {
                                    HStack(spacing: 3) {
                                        Text("Voir")
                                            .font(.caption2.weight(.semibold))
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .foregroundStyle(color)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .background(color.opacity(0.14), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 2)
                            } else {
                                Image(systemName: "opticaldisc")
                                    .font(.title)
                                    .foregroundStyle(Color.spinlogPink)
                                    .padding(.bottom, 2)

                                Text("\(viewModel.genreDistribution.count) genres")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text("Toucher une portion")
                                    .font(.caption2)
                                    .foregroundStyle(Color.appSecondaryText)
                            }
                        }
                        .padding(.horizontal, 30)
                        .allowsHitTesting(selectedGenreName != nil)
                    }
                    .padding(.vertical, 14)

                    // Détail par style musical au sein du genre sélectionné, dans le même
                    // esprit que le détail par taille de vinyle sous "Répartition par support" :
                    // un fondu discret sous le camembert plutôt qu'une 2e couronne permanente.
                    if let selectedGenreName, !viewModel.styleBreakdown(forGenre: selectedGenreName).isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Détail par style")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.appTertiaryText)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(viewModel.styleBreakdown(forGenre: selectedGenreName)) { entry in
                                        Button {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            let items = viewModel.items(forGenre: selectedGenreName, style: entry.name)
                                            selectedMediaFormatData = MediaFormatReleasesSheetData(
                                                title: "\(entry.name) · \(selectedGenreName)",
                                                items: items
                                            )
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(entry.name)
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(Color.spinlogPink)
                                                Text("\(entry.count)")
                                                    .font(.caption2.weight(.medium))
                                                    .foregroundStyle(Color.appSecondaryText)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.spinlogPink.opacity(0.1), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(10)
                .appleMusicGroupedCard()
                .onChange(of: selectedAngle) { _, newAngle in
                    if let newAngle {
                        updateSelectionFromAngle(newAngle)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedGenreName)
            }
        }
    }

    private func handlePieChartTap(at location: CGPoint, in size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let dist = sqrt(dx * dx + dy * dy)
        let maxR = min(size.width, size.height) / 2
        let innerR = maxR * 0.55

        if dist < innerR {
            if let current = selectedGenreName {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                let items = viewModel.items(forGenre: current)
                selectedGenreData = GenreReleasesSheetData(genre: current, items: items)
            }
            return
        }

        guard dist <= maxR * 1.15 else {
            if selectedGenreName != nil {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    selectedGenreName = nil
                }
            }
            return
        }

        var angle = atan2(dx, -dy)
        if angle < 0 {
            angle += 2 * .pi
        }

        let total = Double(viewModel.genreDistribution.map(\.count).reduce(0, +))
        guard total > 0 else { return }
        let targetValue = (angle / (2 * .pi)) * total

        var accumulated: Double = 0
        for entry in viewModel.genreDistribution {
            accumulated += Double(entry.count)
            if targetValue <= accumulated {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if selectedGenreName == entry.name {
                        let items = viewModel.items(forGenre: entry.name)
                        selectedGenreData = GenreReleasesSheetData(genre: entry.name, items: items)
                    } else {
                        selectedGenreName = entry.name
                    }
                }
                return
            }
        }
    }

    private func updateSelectionFromAngle(_ angle: Double) {
        var accumulated: Double = 0
        for entry in viewModel.genreDistribution {
            accumulated += Double(entry.count)
            if angle <= accumulated {
                if selectedGenreName != entry.name {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedGenreName = entry.name
                    }
                }
                break
            }
        }
    }

    private func genreColor(for name: String, index: Int) -> Color {
        if name == StatsViewModel.othersLabel || name == StatsViewModel.unspecifiedLabel {
            return Color(white: 0.55)
        }
        let palette: [Color] = [
            Color.spinlogPink,
            Color(red: 0.58, green: 0.35, blue: 0.88),
            Color(red: 0.28, green: 0.52, blue: 0.95),
            Color(red: 0.16, green: 0.72, blue: 0.74),
            Color(red: 0.98, green: 0.58, blue: 0.22),
            Color(red: 0.95, green: 0.75, blue: 0.25),
            Color(red: 0.30, green: 0.78, blue: 0.55),
            Color(red: 0.88, green: 0.30, blue: 0.45)
        ]
        return palette[index % palette.count]
    }

    // MARK: - Graphique Camembert : Répartition par Support Physique

    private var mediaFormatDistributionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow(title: "Répartition par support", icon: "square.stack.3d.up.fill")

            if viewModel.isLoadingHistogram && viewModel.mediaFormatDistribution.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .appleMusicGroupedCard()
            } else if viewModel.mediaFormatDistribution.isEmpty {
                Text("Pas encore assez de données de support.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .appleMusicGroupedCard()
            } else {
                VStack(spacing: 0) {
                    ZStack {
                        Chart(Array(viewModel.mediaFormatDistribution.enumerated()), id: \.element.id) { index, entry in
                            let isSelected = selectedMediaFormatName == entry.name
                            SectorMark(
                                angle: .value("Exemplaires", entry.count),
                                innerRadius: .ratio(isSelected ? 0.58 : 0.62),
                                outerRadius: .ratio(isSelected ? 1.0 : 0.94),
                                angularInset: 1.5
                            )
                            .cornerRadius(5)
                            .foregroundStyle(mediaFormatColor(for: entry.name))
                            .opacity(selectedMediaFormatName == nil || isSelected ? 1.0 : 0.35)
                        }
                        .chartAngleSelection(value: $selectedMediaFormatAngle)
                        .frame(height: 230)
                        .chartOverlay { proxy in
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture { location in
                                        handleMediaFormatPieTap(at: location, in: geo.size)
                                    }
                                    .accessibilityLabel("Sélectionner une part du graphique de répartition par support")
                                    .accessibilityAddTraits(.isButton)
                            }
                        }

                        // Données dynamiques affichées au centre du camembert
                        VStack(spacing: 4) {
                            if let selected = viewModel.mediaFormatDistribution.first(where: { $0.name == selectedMediaFormatName }) {
                                let color = mediaFormatColor(for: selected.name)

                                Text(selected.name)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)

                                Text((selected.percentage / 100).formatted(.percent.precision(.fractionLength(0))))
                                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                                    .foregroundStyle(color)

                                Text("\(selected.count) exemplaires")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Color.appSecondaryText)

                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    let items = viewModel.items(forMediaFormat: selected.name)
                                    selectedMediaFormatData = MediaFormatReleasesSheetData(title: selected.name, items: items)
                                } label: {
                                    HStack(spacing: 3) {
                                        Text("Voir")
                                            .font(.caption2.weight(.semibold))
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .foregroundStyle(color)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .background(color.opacity(0.14), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 2)
                            } else {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.title)
                                    .foregroundStyle(Color.spinlogPink)
                                    .padding(.bottom, 2)

                                Text("\(viewModel.mediaFormatDistribution.count) supports")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text("Toucher une portion")
                                    .font(.caption2)
                                    .foregroundStyle(Color.appSecondaryText)
                            }
                        }
                        .padding(.horizontal, 30)
                        .allowsHitTesting(selectedMediaFormatName != nil)
                    }
                    .padding(.vertical, 14)

                    // Détail par taille de vinyle (12"/10"/7") : n'apparaît que lorsque la part
                    // "Vinyles" est sélectionnée, dans un fondu discret sous le camembert — c'est
                    // la façon la plus lisible de montrer une sous-catégorie sans surcharger le
                    // graphique principal d'une 2e couronne en permanence.
                    if selectedMediaFormatName == ShelfMediaCategory.vinyl12.broadFormatLabel, !viewModel.vinylSizeBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Détail par taille")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.appTertiaryText)

                            HStack(spacing: 8) {
                                ForEach(viewModel.vinylSizeBreakdown) { entry in
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        let items = viewModel.items(forShelfCategory: entry.category)
                                        selectedMediaFormatData = MediaFormatReleasesSheetData(
                                            title: entry.category.displayName,
                                            items: items
                                        )
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(entry.label)
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(Color.spinlogPink)
                                            Text("\(entry.count)")
                                                .font(.caption2.weight(.medium))
                                                .foregroundStyle(Color.appSecondaryText)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.spinlogPink.opacity(0.1), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 10)
                .appleMusicGroupedCard()
                .onChange(of: selectedMediaFormatAngle) { _, newAngle in
                    if let newAngle {
                        updateMediaFormatSelectionFromAngle(newAngle)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedMediaFormatName)
            }
        }
    }

    private func handleMediaFormatPieTap(at location: CGPoint, in size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let dist = sqrt(dx * dx + dy * dy)
        let maxR = min(size.width, size.height) / 2
        let innerR = maxR * 0.55

        if dist < innerR {
            if let current = selectedMediaFormatName {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                let items = viewModel.items(forMediaFormat: current)
                selectedMediaFormatData = MediaFormatReleasesSheetData(title: current, items: items)
            }
            return
        }

        guard dist <= maxR * 1.15 else {
            if selectedMediaFormatName != nil {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    selectedMediaFormatName = nil
                }
            }
            return
        }

        var angle = atan2(dx, -dy)
        if angle < 0 {
            angle += 2 * .pi
        }

        let total = Double(viewModel.mediaFormatDistribution.map(\.count).reduce(0, +))
        guard total > 0 else { return }
        let targetValue = (angle / (2 * .pi)) * total

        var accumulated: Double = 0
        for entry in viewModel.mediaFormatDistribution {
            accumulated += Double(entry.count)
            if targetValue <= accumulated {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if selectedMediaFormatName == entry.name {
                        let items = viewModel.items(forMediaFormat: entry.name)
                        selectedMediaFormatData = MediaFormatReleasesSheetData(title: entry.name, items: items)
                    } else {
                        selectedMediaFormatName = entry.name
                    }
                }
                return
            }
        }
    }

    private func updateMediaFormatSelectionFromAngle(_ angle: Double) {
        var accumulated: Double = 0
        for entry in viewModel.mediaFormatDistribution {
            accumulated += Double(entry.count)
            if angle <= accumulated {
                if selectedMediaFormatName != entry.name {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedMediaFormatName = entry.name
                    }
                }
                break
            }
        }
    }

    private func mediaFormatColor(for name: String) -> Color {
        // Comparé aux libellés traduits de `ShelfMediaCategory` (mêmes valeurs que les parts).
        switch name {
        case ShelfMediaCategory.vinyl12.broadFormatLabel: return Color.spinlogPink
        case ShelfMediaCategory.cd.broadFormatLabel: return Color(red: 0.28, green: 0.52, blue: 0.95)
        case ShelfMediaCategory.cassette.broadFormatLabel: return Color(red: 0.98, green: 0.58, blue: 0.22)
        default: return Color(white: 0.55)
        }
    }

    // MARK: - Graphique Camembert : Répartition par Label

    private var labelDistributionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow(title: "Répartition par label", icon: "tag.fill")

            if viewModel.isLoadingHistogram && viewModel.labelDistribution.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .appleMusicGroupedCard()
            } else if viewModel.labelDistribution.isEmpty {
                Text("Pas encore assez de données de label.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .appleMusicGroupedCard()
            } else {
                VStack(spacing: 0) {
                    ZStack {
                        Chart(Array(viewModel.labelDistribution.enumerated()), id: \.element.id) { index, entry in
                            let isSelected = selectedLabelName == entry.name
                            SectorMark(
                                angle: .value("Occurrences", entry.count),
                                innerRadius: .ratio(isSelected ? 0.58 : 0.62),
                                outerRadius: .ratio(isSelected ? 1.0 : 0.94),
                                angularInset: 1.5
                            )
                            .cornerRadius(5)
                            .foregroundStyle(genreColor(for: entry.name, index: index))
                            .opacity(selectedLabelName == nil || isSelected ? 1.0 : 0.35)
                        }
                        .chartAngleSelection(value: $selectedLabelAngle)
                        .frame(height: 230)
                        .chartOverlay { proxy in
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture { location in
                                        handleLabelPieTap(at: location, in: geo.size)
                                    }
                                    .accessibilityLabel("Sélectionner une part du graphique de répartition par label")
                                    .accessibilityAddTraits(.isButton)
                            }
                        }

                        // Données dynamiques affichées au centre du camembert
                        VStack(spacing: 4) {
                            if let selected = viewModel.labelDistribution.first(where: { $0.name == selectedLabelName }) {
                                let color = genreColor(for: selected.name, index: viewModel.labelDistribution.firstIndex(where: { $0.name == selected.name }) ?? 0)

                                Text(selected.name)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)

                                Text((selected.percentage / 100).formatted(.percent.precision(.fractionLength(0))))
                                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                                    .foregroundStyle(color)

                                Text("\(selected.count) albums")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Color.appSecondaryText)

                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    let items = viewModel.items(forLabel: selected.name)
                                    selectedMediaFormatData = MediaFormatReleasesSheetData(title: selected.name, items: items)
                                } label: {
                                    HStack(spacing: 3) {
                                        Text("Voir")
                                            .font(.caption2.weight(.semibold))
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .foregroundStyle(color)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .background(color.opacity(0.14), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 2)
                            } else {
                                Image(systemName: "tag.fill")
                                    .font(.title)
                                    .foregroundStyle(Color.spinlogPink)
                                    .padding(.bottom, 2)

                                Text("\(viewModel.labelDistribution.count) labels")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text("Toucher une portion")
                                    .font(.caption2)
                                    .foregroundStyle(Color.appSecondaryText)
                            }
                        }
                        .padding(.horizontal, 30)
                        .allowsHitTesting(selectedLabelName != nil)
                    }
                    .padding(.vertical, 14)
                }
                .padding(10)
                .appleMusicGroupedCard()
                .onChange(of: selectedLabelAngle) { _, newAngle in
                    if let newAngle {
                        updateLabelSelectionFromAngle(newAngle)
                    }
                }
            }
        }
    }

    private func handleLabelPieTap(at location: CGPoint, in size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let dist = sqrt(dx * dx + dy * dy)
        let maxR = min(size.width, size.height) / 2
        let innerR = maxR * 0.55

        if dist < innerR {
            if let current = selectedLabelName {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                let items = viewModel.items(forLabel: current)
                selectedMediaFormatData = MediaFormatReleasesSheetData(title: current, items: items)
            }
            return
        }

        guard dist <= maxR * 1.15 else {
            if selectedLabelName != nil {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    selectedLabelName = nil
                }
            }
            return
        }

        var angle = atan2(dx, -dy)
        if angle < 0 {
            angle += 2 * .pi
        }

        let total = Double(viewModel.labelDistribution.map(\.count).reduce(0, +))
        guard total > 0 else { return }
        let targetValue = (angle / (2 * .pi)) * total

        var accumulated: Double = 0
        for entry in viewModel.labelDistribution {
            accumulated += Double(entry.count)
            if targetValue <= accumulated {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if selectedLabelName == entry.name {
                        let items = viewModel.items(forLabel: entry.name)
                        selectedMediaFormatData = MediaFormatReleasesSheetData(title: entry.name, items: items)
                    } else {
                        selectedLabelName = entry.name
                    }
                }
                return
            }
        }
    }

    private func updateLabelSelectionFromAngle(_ angle: Double) {
        var accumulated: Double = 0
        for entry in viewModel.labelDistribution {
            accumulated += Double(entry.count)
            if angle <= accumulated {
                if selectedLabelName != entry.name {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedLabelName = entry.name
                    }
                }
                break
            }
        }
    }

    // MARK: - Histogramme : Années originales de sortie (Master Year)

    @ViewBuilder
    private func originalYearsHistogramSection(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow(title: "Sorties originales", icon: "calendar")
                .id("originalYearsTitle")

            Picker("Granularité", selection: $originalYearsGranularity.animation(.easeInOut(duration: 0.2))) {
                ForEach(OriginalYearsGranularity.allCases) { granularity in
                    Text(granularity.label).tag(granularity)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: originalYearsGranularity) {
                selectedOriginalYear = nil
                selectedYearData = nil
            }

            if currentOriginalYearsDistribution.count > maxVisibleBars {
                (originalYearsGranularity == .decade
                    ? Text("Glisser latéralement pour afficher les autres décennies")
                    : Text("Glisser latéralement pour afficher les autres années"))
                    .font(.caption2)
                    .foregroundStyle(Color.appSecondaryText)
            }

            if viewModel.isLoadingHistogram && currentOriginalYearsDistribution.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .appleMusicGroupedCard()
            } else if currentOriginalYearsDistribution.isEmpty {
                Text("Pas encore assez de données.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .appleMusicGroupedCard()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    let totalBars = currentOriginalYearsDistribution.count
                    let hasScroll = totalBars > maxVisibleBars

                    GeometryReader { containerGeo in
                        let availableWidth = containerGeo.size.width
                        let stepWidth = availableWidth / CGFloat(maxVisibleBars)
                        let chartWidth = hasScroll ? stepWidth * CGFloat(totalBars) : availableWidth

                        ScrollView(.horizontal, showsIndicators: false) {
                            Chart(currentOriginalYearsDistribution, id: \.year) { entry in
                                BarMark(
                                    x: .value("Année", String(entry.year)),
                                    y: .value("Albums", entry.count)
                                )
                                .foregroundStyle(originalBarStyle(for: entry.year))
                                .cornerRadius(5)
                                .annotation(position: .top, spacing: 4) {
                                    annotationBadge(isSelected: selectedOriginalYear == String(entry.year), count: entry.count)
                                }
                            }
                            .chartYScale(domain: 0...(max(1, Int(Double(maxOriginalYearsCount) * 1.25))))
                            .chartOverlay { proxy in
                                GeometryReader { geometry in
                                    Rectangle()
                                        .fill(Color.clear)
                                        .contentShape(Rectangle())
                                        .accessibilityLabel("Sélectionner une année de sortie originale")
                                        .accessibilityAddTraits(.isButton)
                                        .onTapGesture { location in
                                            guard let plotFrame = proxy.plotFrame else { return }
                                            let origin = geometry[plotFrame].origin
                                            let relativeX = location.x - origin.x
                                            if let tappedYear: String = proxy.value(atX: relativeX),
                                               let entry = currentOriginalYearsDistribution.first(where: { String($0.year) == tappedYear }) {
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                let year = entry.year

                                                if selectedOriginalYear == tappedYear && selectedYearData != nil {
                                                    withAnimation(.easeInOut(duration: 0.25)) {
                                                        selectedOriginalYear = nil
                                                        selectedYearData = nil
                                                    }
                                                } else {
                                                    let items: [CollectionItem]
                                                    let title: String
                                                    switch originalYearsGranularity {
                                                    case .year:
                                                        items = viewModel.items(forOriginalYear: year)
                                                        title = String(localized: "Sortis en \(String(year))")
                                                    case .decade:
                                                        items = viewModel.items(forOriginalDecade: year)
                                                        title = String(localized: "Sortis dans les années \(String(year))")
                                                    }
                                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                                        selectedOriginalYear = tappedYear
                                                        selectedAdditionsYear = nil
                                                        selectedYearData = YearReleasesSheetData(
                                                            year: year,
                                                            items: items,
                                                            type: "originalYears",
                                                            title: title
                                                        )
                                                    }

                                                    Task { @MainActor in
                                                        try? await Task.sleep(for: AppTiming.scrollSettleDelay)
                                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                                            scrollProxy.scrollTo("originalYearsTitle", anchor: .top)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                }
                            }
                            .frame(width: chartWidth, height: 160)
                        }
                        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    }
                    .frame(height: 160)

                    // Indicateur de progression discret en bas du graphique
                    if viewModel.isResolvingMasters {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)

                            Text("Recherche des années originales : \(viewModel.masterResolutionProgress.formatted(.percent.precision(.fractionLength(0))))")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)

                            Spacer()

                            if viewModel.missingMastersCount > 0 {
                                Text("\(viewModel.missingMastersCount) restants")
                                    .font(.caption2)
                                    .foregroundStyle(Color.appTertiaryText)
                            }
                        }
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(12)
                .appleMusicGroupedCard()
            }
        }
    }

    // MARK: - Histogramme : Exemplaires ajoutés par année

    @ViewBuilder
    private func additionsHistogramSection(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow(title: "Exemplaires ajoutés par année", icon: "chart.bar.xaxis")
                .id("additionsTitle")

            if viewModel.additionsPerYear.count > maxVisibleBars {
                Text("Glisser latéralement pour afficher les autres années")
                    .font(.caption2)
                    .foregroundStyle(Color.appSecondaryText)
            }

            if viewModel.isLoadingHistogram && viewModel.additionsPerYear.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .appleMusicGroupedCard()
            } else if viewModel.additionsPerYear.isEmpty {
                Text("Pas encore assez de données.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .appleMusicGroupedCard()
            } else {
                let totalBars = viewModel.additionsPerYear.count
                let hasScroll = totalBars > maxVisibleBars

                GeometryReader { containerGeo in
                    let availableWidth = containerGeo.size.width
                    let stepWidth = availableWidth / CGFloat(maxVisibleBars)
                    let chartWidth = hasScroll ? stepWidth * CGFloat(totalBars) : availableWidth

                    ScrollView(.horizontal, showsIndicators: false) {
                        Chart(viewModel.additionsPerYear, id: \.year) { entry in
                            BarMark(
                                x: .value("Année", String(entry.year)),
                                y: .value("Ajouts", entry.count)
                            )
                            .foregroundStyle(additionsBarStyle(for: entry.year))
                            .cornerRadius(5)
                            .annotation(position: .top, spacing: 4) {
                                annotationBadge(isSelected: selectedAdditionsYear == String(entry.year), count: entry.count)
                            }
                        }
                        .chartYScale(domain: 0...(max(1, Int(Double(maxAdditionsCount) * 1.25))))
                        .chartOverlay { proxy in
                            GeometryReader { geometry in
                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .accessibilityLabel("Sélectionner une année d'ajout à la collection")
                                    .accessibilityAddTraits(.isButton)
                                    .onTapGesture { location in
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let origin = geometry[plotFrame].origin
                                        let relativeX = location.x - origin.x
                                        if let tappedYear: String = proxy.value(atX: relativeX),
                                           let entry = viewModel.additionsPerYear.first(where: { String($0.year) == tappedYear }) {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            let year = entry.year

                                            if selectedAdditionsYear == tappedYear && selectedYearData != nil {
                                                withAnimation(.easeInOut(duration: 0.25)) {
                                                    selectedAdditionsYear = nil
                                                    selectedYearData = nil
                                                }
                                            } else {
                                                let items = viewModel.items(forYear: year)
                                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                                    selectedAdditionsYear = tappedYear
                                                    selectedOriginalYear = nil
                                                    selectedYearData = YearReleasesSheetData(
                                                        year: year,
                                                        items: items,
                                                        type: "additions",
                                                        title: String(localized: "Ajoutés en \(String(year))")
                                                    )
                                                }

                                                Task { @MainActor in
                                                    try? await Task.sleep(for: AppTiming.scrollSettleDelay)
                                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                                        scrollProxy.scrollTo("additionsTitle", anchor: .top)
                                                    }
                                                }
                                            }
                                        }
                                    }
                            }
                        }
                        .frame(width: chartWidth, height: 160)
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                }
                .frame(height: 160)
                .padding(12)
                .appleMusicGroupedCard()
            }
        }
    }

    /// Contrairement aux histogrammes verticaux (dégradé haut→bas, qui suit leur longueur),
    /// les barres du classement des artistes sont horizontales : le dégradé doit donc suivre
    /// le sens gauche→droite pour accompagner la longueur réelle de la barre.
    private var topArtistBarGradient: LinearGradient {
        LinearGradient(
            colors: [Color.chartPinkSoftTop, Color.chartPinkSoftBottom],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func originalBarStyle(for year: Int) -> LinearGradient {
        if selectedOriginalYear == nil || selectedOriginalYear == String(year) {
            return Color.spinlogChartGradient
        } else {
            return Color.spinlogChartDimmedGradient
        }
    }

    private func additionsBarStyle(for year: Int) -> LinearGradient {
        if selectedAdditionsYear == nil || selectedAdditionsYear == String(year) {
            return Color.spinlogChartGradient
        } else {
            return Color.spinlogChartDimmedGradient
        }
    }

    @ViewBuilder
    private func annotationBadge(isSelected: Bool, count: Int) -> some View {
        if isSelected {
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color.buttonPinkTop, Color.buttonPinkBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .shadow(color: Color.buttonPinkBottom.opacity(0.35), radius: 4, y: 1.5)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    @ViewBuilder
    private var valuationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Estimation de la collection", icon: "banknote.fill")
            if viewModel.isLoadingValuation {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .appleMusicGroupedCard()
            } else if let value = viewModel.collectionValue {
                VStack(spacing: 0) {
                    valuationRow(title: "Minimum", value: value.minimum)
                    Divider().opacity(0.15).padding(.leading, 14)
                    valuationRow(title: "Médiane", value: value.median)
                    Divider().opacity(0.15).padding(.leading, 14)
                    valuationRow(title: "Maximum", value: value.maximum)
                }
                .padding(.vertical, 4)
                .appleMusicGroupedCard()
                Text("Basée sur l'historique réel des ventes Discogs pour les disques de ta collection.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            } else {
                Text("Estimation indisponible pour le moment.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .appleMusicGroupedCard()
            }
        }
    }

    @ViewBuilder
    private var valueHistorySection: some View {
        if viewModel.valueHistoryPoints.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(title: "Évolution de la cote", icon: "chart.line.uptrend.xyaxis")

                Chart(Array(viewModel.valueHistoryPoints.enumerated()), id: \.offset) { _, point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Minimum", point.low),
                        yEnd: .value("Maximum", point.high)
                    )
                    .foregroundStyle(Color.spinlogPink.opacity(0.12))

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Médiane", point.median)
                    )
                    .foregroundStyle(Color.spinlogPink)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .frame(height: 160)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .appleMusicGroupedCard()

                Text("Zone claire = fourchette basse/haute Discogs ; ligne = valeur médiane.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            }
        }
    }

    @ViewBuilder
    private var investedVsValueSection: some View {
        if !premiumStore.isPremium {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(title: "Investi vs Cote actuelle", icon: "arrow.left.arrow.right.circle.fill")
                premiumLockedInvestedCard
            }
        } else if let invested = viewModel.totalInvested, let value = viewModel.collectionValue,
           let median = PurchasePriceParser.parseFormattedDiscogsAmount(value.median) {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(title: "Investi vs Cote actuelle", icon: "arrow.left.arrow.right.circle.fill")

                VStack(spacing: 0) {
                    HStack {
                        Text("Total investi")
                            .font(.subheadline)
                        Spacer()
                        Text(invested.formatted(.currency(code: viewModel.totalInvestedCurrency)))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider().opacity(0.15).padding(.leading, 14)

                    HStack {
                        Text("Cote actuelle")
                            .font(.subheadline)
                        Spacer()
                        Text(value.median)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.spinlogPink)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider().opacity(0.15).padding(.leading, 14)

                    let gain = median.amount - invested
                    let percent = invested > 0 ? (gain / invested) : 0
                    HStack {
                        Text("Plus-value latente")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(gain >= 0 ? "+" : "")\(gain.formatted(.currency(code: median.currency).precision(.fractionLength(0)))) (\(percent.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))))")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(gain >= 0 ? Color.gainPositive : Color.gainNegative)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .appleMusicGroupedCard()

                Text("Le total investi ne compte que les exemplaires dont le prix d'achat est renseigné.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            }
        }
    }

    private var premiumLockedInvestedCard: some View {
        PremiumLockedCard(
            icon: "arrow.left.arrow.right.circle.fill",
            title: "Suivi de cote",
            message: "Passe premium pour comparer ton investissement à la cote actuelle et suivre ta plus-value."
        )
    }

    private func valuationRow(title: LocalizedStringResource, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.spinlogPink)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Tops & Palmarès d'écoute

    @ViewBuilder
    private var listeningStatsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Tops & Palmarès", icon: "waveform")

            if !premiumStore.isPremium {
                PremiumLockedCard(
                    icon: "waveform",
                    title: "Palmarès d'écoute sur platine",
                    message: viewModel.totalListeningSessionsCount > 0
                        ? "Tu as déjà enregistré \(viewModel.totalListeningSessionsCount) écoutes sur platine. Passe premium pour révéler tes classements, artistes favoris et podiums !"
                        : "Passe premium pour révéler tes classements d'albums et artistes les plus écoutés sur platine, podiums mensuels et annuels."
                )
            } else if viewModel.totalListeningSessionsCount < StatsViewModel.minimumListeningSessionsForRanking {
                notEnoughListeningDataCard(
                    "Enregistre au moins \(StatsViewModel.minimumListeningSessionsForRanking) écoutes sur platine (bouton J'écoute d'une fiche album) pour débloquer tes classements."
                )
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    topEntitiesCard
                    podiumSection
                    Text("Basé sur tes écoutes sur platine. Les lectures Apple Music ne sont pas comptées.")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
        }
    }

    /// Classements des albums et artistes les plus écoutés, au même endroit : le même geste
    /// (segmented Picker) que pour la période du podium ci-dessous permet de passer de l'un à
    /// l'autre sans faire défiler deux cartes empilées séparément.
    @ViewBuilder
    private var topEntitiesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(title: "Les plus écoutés", style: .subsection)

            Picker("Classement", selection: $topEntityKind.animation(.easeInOut(duration: 0.2))) {
                ForEach(TopEntityKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            switch topEntityKind {
            case .albums:
                let visibleAlbums = Array(viewModel.topAlbums.prefix(20).enumerated())
                // 5 lignes visibles par défaut, jusqu'à 20 en faisant défiler verticalement —
                // même convention que le classement des artistes ci-dessous (pochette 44pt, donc
                // une rowHeight un peu plus grande).
                let rowHeight: CGFloat = 64
                let fullHeight = CGFloat(visibleAlbums.count) * rowHeight
                let visibleHeight = min(fullHeight, rowHeight * 5)

                if visibleAlbums.count > 5 {
                    Text("Faire défiler verticalement pour afficher les autres albums")
                        .font(.caption2)
                        .foregroundStyle(Color.appSecondaryText)
                }

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(visibleAlbums, id: \.element.id) { index, entry in
                            if index > 0 {
                                Divider().opacity(0.15).padding(.leading, 14)
                            }
                            topAlbumRow(rank: index + 1, entry: entry)
                        }
                    }
                }
                .frame(height: visibleHeight)
                .appleMusicGroupedCard()
            case .artists:
                let visibleArtists = Array(viewModel.topArtists.prefix(20).enumerated())
                // 5 lignes visibles par défaut, jusqu'à 20 en faisant défiler verticalement —
                // même convention que `topArtistsSection` ci-dessus (rowHeight approximative,
                // indice textuel affiché seulement s'il y a effectivement plus à découvrir).
                let rowHeight: CGFloat = 56
                let fullHeight = CGFloat(visibleArtists.count) * rowHeight
                let visibleHeight = min(fullHeight, rowHeight * 5)

                if visibleArtists.count > 5 {
                    Text("Faire défiler verticalement pour afficher les autres artistes")
                        .font(.caption2)
                        .foregroundStyle(Color.appSecondaryText)
                }

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(visibleArtists, id: \.element.id) { index, entry in
                            if index > 0 {
                                Divider().opacity(0.15).padding(.leading, 14)
                            }
                            topArtistRow(rank: index + 1, entry: entry)
                        }
                    }
                }
                .frame(height: visibleHeight)
                .appleMusicGroupedCard()
            }
        }
    }

    @ViewBuilder
    private var podiumSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(title: "Podium", style: .subsection)

            Picker("Période du podium", selection: $podiumPeriod.animation(.easeInOut(duration: 0.2))) {
                ForEach(PodiumPeriod.allCases) { period in
                    Text(period.label).tag(period)
                }
            }
            .pickerStyle(.segmented)

            switch podiumPeriod {
            case .yearly:
                if viewModel.yearlyListeningSessionsCount < StatsViewModel.minimumListeningSessionsForRanking {
                    notEnoughListeningDataCard("Pas assez d'écoutes cette année pour un podium pertinent (minimum \(StatsViewModel.minimumListeningSessionsForRanking)).")
                } else {
                    podiumStage(entries: viewModel.yearlyPodium)
                }
            case .monthly:
                if viewModel.monthlyListeningSessionsCount < StatsViewModel.minimumListeningSessionsForRanking {
                    notEnoughListeningDataCard("Pas assez d'écoutes ce mois-ci pour un podium pertinent (minimum \(StatsViewModel.minimumListeningSessionsForRanking)).")
                } else {
                    podiumStage(entries: viewModel.monthlyPodium)
                }
            }
        }
    }

    /// Podium stylisé façon estrade : les 3 pochettes posées sur des marches de hauteur
    /// décroissante (1ʳᵉ place au centre, plus haute), teintées or/argent/bronze.
    private func podiumStage(entries: [TopAlbumEntry]) -> some View {
        let first = entries.first
        let second = entries.count > 1 ? entries[1] : nil
        let third = entries.count > 2 ? entries[2] : nil

        return HStack(alignment: .bottom, spacing: 10) {
            Spacer(minLength: 0)
            podiumColumn(entry: second, rank: 2)
            podiumColumn(entry: first, rank: 1)
            podiumColumn(entry: third, rank: 3)
            Spacer(minLength: 0)
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
        .appleMusicGroupedCard()
    }

    @ViewBuilder
    private func podiumColumn(entry: TopAlbumEntry?, rank: Int) -> some View {
        if let entry {
            NavigationLink(value: SearchDestination.release(
                entry.item.releaseId,
                coverURL: entry.item.basicInformation.coverImage ?? entry.item.basicInformation.thumb
            )) {
                VStack(spacing: 6) {
                    AsyncCoverImage(url: entry.item.basicInformation.coverImage ?? entry.item.basicInformation.thumb, cornerRadius: 8, targetSize: podiumCoverSize(for: rank))
                        .frame(width: podiumCoverSize(for: rank), height: podiumCoverSize(for: rank))
                        .shadow(color: .black.opacity(0.2), radius: 5, y: 3)

                    Text(entry.item.basicInformation.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("\(entry.playCount) écoutes")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.spinlogPink)
                        .lineLimit(1)

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(podiumPedestalGradient(for: rank))
                        .frame(width: 76, height: podiumPedestalHeight(for: rank))
                        .overlay(alignment: .top) {
                            Text("\(rank)")
                                .font(.headline.weight(.heavy))
                                .foregroundStyle(.white)
                                .padding(.top, 6)
                        }
                }
                .frame(width: 86)
            }
            .buttonStyle(.plain)
        }
    }

    private func podiumCoverSize(for rank: Int) -> CGFloat {
        switch rank {
        case 1: return 72
        case 2: return 60
        default: return 52
        }
    }

    private func podiumPedestalHeight(for rank: Int) -> CGFloat {
        switch rank {
        case 1: return 64
        case 2: return 46
        default: return 32
        }
    }

    private func podiumPedestalGradient(for rank: Int) -> LinearGradient {
        switch rank {
        case 1:
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.85, blue: 0.4), Color(red: 0.82, green: 0.62, blue: 0.13)],
                startPoint: .top, endPoint: .bottom
            )
        case 2:
            return LinearGradient(
                colors: [Color(white: 0.85), Color(white: 0.64)],
                startPoint: .top, endPoint: .bottom
            )
        default:
            return LinearGradient(
                colors: [Color(red: 0.80, green: 0.55, blue: 0.35), Color(red: 0.62, green: 0.40, blue: 0.24)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private func topAlbumRow(rank: Int, entry: TopAlbumEntry) -> some View {
        NavigationLink(value: SearchDestination.release(
            entry.item.releaseId,
            coverURL: entry.item.basicInformation.coverImage ?? entry.item.basicInformation.thumb
        )) {
            HStack(spacing: 12) {
                rankBadge(rank)

                AsyncCoverImage(url: entry.item.basicInformation.coverImage ?? entry.item.basicInformation.thumb, cornerRadius: 8, targetSize: 44)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.item.basicInformation.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(entry.item.basicInformation.artistNames)
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("\(entry.playCount) écoutes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.spinlogPink)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.appTertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func topArtistRow(rank: Int, entry: TopArtistEntry) -> some View {
        HStack(spacing: 12) {
            rankBadge(rank)

            ArtistThumbnailView(artistName: entry.name)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                // Même unité que le classement des albums (« écoutes », plus « sessions ») ; deux
                // textes imbriqués pour que chaque nombre ait sa propre règle de pluriel.
                Text("\(Text("\(entry.totalPlays) écoutes")) · \(Text("\(entry.releaseCount) disques"))")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Photo circulaire de l'artiste récupérée sur Apple Music (voir
    /// `AppleMusicArtistArtworkService`), avec repli silencieux sur l'icône micro générique si
    /// l'autorisation est refusée, l'artiste n'est pas trouvé dans le catalogue, ou hors ligne.
    private struct ArtistThumbnailView: View {
        let artistName: String
        @State private var artworkURL: URL?

        var body: some View {
            Group {
                if let artworkURL {
                    KFImage(artworkURL)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "music.mic")
                                .font(.title3)
                                .foregroundStyle(Color.spinlogPink)
                        }
                }
            }
            .task(id: artistName) {
                artworkURL = await AppleMusicArtistArtworkService.shared.artworkURL(for: artistName)
            }
        }
    }

    @ViewBuilder
    private func rankBadge(_ rank: Int) -> some View {
        switch rank {
        case 1:
            Text("🥇").font(.title3).frame(width: 24)
        case 2:
            Text("🥈").font(.title3).frame(width: 24)
        case 3:
            Text("🥉").font(.title3).frame(width: 24)
        default:
            Text("\(rank)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.appTertiaryText)
                .frame(width: 24)
        }
    }

    private func notEnoughListeningDataCard(_ message: LocalizedStringKey) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(Color.appSecondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(.horizontal, 14)
            .appleMusicGroupedCard()
    }
}

private struct GenreReleasesSheetView: View {
    let data: GenreReleasesSheetData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if data.items.isEmpty {
                    ContentUnavailableView(
                        "Aucun élément",
                        systemImage: "opticaldisc",
                        description: Text("Aucun album trouvé pour ce genre.")
                    )
                } else {
                    List {
                        ForEach(data.items) { item in
                            NavigationLink(value: SearchDestination.release(
                                item.releaseId,
                                coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb
                            )) {
                                CollectionRow(item: item)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("\(data.genre) · \(data.items.count) albums")
            .navigationBarTitleDisplayMode(.inline)
            .searchDestinations()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
    }
}

private struct MediaFormatReleasesSheetView: View {
    let data: MediaFormatReleasesSheetData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if data.items.isEmpty {
                    ContentUnavailableView(
                        "Aucun élément",
                        systemImage: "opticaldisc",
                        description: Text("Aucun album trouvé pour ce support.")
                    )
                } else {
                    List {
                        ForEach(data.items) { item in
                            NavigationLink(value: SearchDestination.release(
                                item.releaseId,
                                coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb
                            )) {
                                CollectionRow(item: item)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("\(data.title) · \(data.items.count) albums")
            .navigationBarTitleDisplayMode(.inline)
            .searchDestinations()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
    }
}

private struct ArtistReleasesSheetView: View {
    let data: ArtistReleasesSheetData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if data.items.isEmpty {
                    ContentUnavailableView(
                        "Aucun élément",
                        systemImage: "opticaldisc",
                        description: Text("Aucun album trouvé pour cet artiste.")
                    )
                } else {
                    List {
                        ForEach(data.items) { item in
                            NavigationLink(value: SearchDestination.release(
                                item.releaseId,
                                coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb
                            )) {
                                CollectionRow(item: item)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("\(data.artist) · \(data.items.count) albums")
            .navigationBarTitleDisplayMode(.inline)
            .searchDestinations()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
    }
}

private struct YearReleasesSheetView: View {
    let data: YearReleasesSheetData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if data.items.isEmpty {
                    ContentUnavailableView(
                        "Aucun élément",
                        systemImage: "opticaldisc",
                        description: Text("Aucun élément trouvé pour cette année.")
                    )
                } else {
                    List {
                        ForEach(data.items) { item in
                            NavigationLink(value: SearchDestination.release(
                                item.releaseId,
                                coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb
                            )) {
                                CollectionRow(item: item)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(Text("\(data.title) · \(data.items.count) éléments"))
            .navigationBarTitleDisplayMode(.inline)
            .searchDestinations()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
    }
}

private struct StatCounterCard: View {
    let title: LocalizedStringResource
    let value: String
    var subtitle: String? = nil
    let systemImage: String
    let tint: Color
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) {
                cardContent
            }
            .buttonStyle(.plain)
        } else {
            cardContent
        }
    }

    /// Contenu partagé entre la variante cliquable (dans un `Button`) et la variante
    /// purement informative (sans action), pour que cette dernière garde ses couleurs
    /// pleines — un `Button` désactivé via `.disabled()` atténue automatiquement son
    /// contenu, ce qu'on ne veut pas ici puisque ce n'est pas un état "indisponible".
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                Spacer()
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.appTertiaryText)
                }
            }

            Text(value)
                .font(.title.bold())
                .monospacedDigit()

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appleMusicGroupedCard()
    }
}
