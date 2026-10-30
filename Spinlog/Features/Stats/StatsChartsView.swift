import SwiftUI
import Charts

/// Classement des artistes et camemberts (genre, support physique, label) de l'onglet Stats —
/// extrait de StatsView.swift (2176 lignes à l'origine) pour isoler cette responsabilité. Voir le
/// commentaire sur `StatsView` : les membres sont `internal` (pas `private`) précisément pour
/// permettre ce découpage en extensions à travers plusieurs fichiers.
///
/// Les camemberts partagent `StatsPieChart` ; sélections et feuilles vivent dans
/// `StatsChartSelection` (voir son commentaire). Chaque ouverture de feuille fait défiler le titre
/// du graphique en haut de l'écran (`scrollToChartTitle`).
extension StatsView {
    // MARK: - Classement des artistes

    @ViewBuilder
    func topArtistsSection(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow(title: "Classement des artistes", icon: "person.2.fill")
                .id("topArtistsTitle")

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
                TopArtistsChart(
                    entries: viewModel.topArtistsByCollectionCount.map { ArtistCount(name: $0.name, count: $0.count) },
                    selection: chartSelection,
                    onSelect: { selectArtist($0, scrollProxy: scrollProxy) }
                )
            }
        }
    }

    // MARK: - Camembert : répartition par genre

    func genreDistributionSection(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow(title: "Répartition par genre", icon: "chart.pie.fill")
                .id("genreTitle")

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
                StatsPieChart(
                    slices: viewModel.genreDistribution.map { PieSlice(name: $0.name, count: $0.count, percentage: $0.percentage) },
                    pie: chartSelection.genre,
                    valueLabel: "Occurrences",
                    accessibilityTitle: Text("Répartition par genre"),
                    valueText: { String(localized: "\($0) albums") },
                    color: { genreColor(for: $0, index: $1) },
                    countText: { LocalizedStringResource("\($0) albums") },
                    emptyIcon: "opticaldisc",
                    totalText: { LocalizedStringResource("\($0) genres") },
                    verticalPadding: 10,
                    onOpen: { openGenreSheet($0, scrollProxy: scrollProxy) },
                    onSelect: { _ in scrollToChartTitle("genreTitle", scrollProxy: scrollProxy) }
                ) { selectedGenre in
                    genreStyleDetail(selectedGenre: selectedGenre, scrollProxy: scrollProxy)
                }
            }
        }
    }

    /// Détail par style musical au sein du genre sélectionné, dans le même esprit que le détail
    /// par taille de vinyle sous « Répartition par support » : un fondu discret sous le camembert
    /// plutôt qu'une 2e couronne permanente.
    @ViewBuilder
    private func genreStyleDetail(selectedGenre: String?, scrollProxy: ScrollViewProxy) -> some View {
        if let selectedGenre {
            let styles = viewModel.styleBreakdown(forGenre: selectedGenre)
            if !styles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Détail par style")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.appTertiaryText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(styles) { entry in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    openMediaFormatSheet(
                                        title: "\(selectedGenre) · \(entry.name)",
                                        items: viewModel.items(forGenre: selectedGenre, style: entry.name),
                                        owner: .none,
                                        titleID: "genreTitle",
                                        scrollProxy: scrollProxy
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
                .motionTransition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    func genreColor(for name: String, index: Int) -> Color {
        if name == StatsViewModel.othersLabel || name == StatsViewModel.unspecifiedLabel {
            return Color.chartNeutral
        }
        let palette = Color.chartPalette
        return palette[index % palette.count]
    }

    // MARK: - Camembert : répartition par support physique

    func mediaFormatDistributionSection(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow(title: "Répartition par support", icon: "square.stack.3d.up.fill")
                .id("mediaFormatTitle")

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
                StatsPieChart(
                    slices: viewModel.mediaFormatDistribution.map { PieSlice(name: $0.name, count: $0.count, percentage: $0.percentage) },
                    pie: chartSelection.mediaFormat,
                    valueLabel: "Exemplaires",
                    accessibilityTitle: Text("Répartition par support"),
                    valueText: { String(localized: "\($0) exemplaires") },
                    color: { name, _ in mediaFormatColor(for: name) },
                    countText: { LocalizedStringResource("\($0) exemplaires") },
                    emptyIcon: "square.stack.3d.up.fill",
                    totalText: { LocalizedStringResource("\($0) supports") },
                    verticalPadding: 0,
                    onOpen: { name in
                        openMediaFormatSheet(
                            title: name,
                            items: viewModel.items(forMediaFormat: name),
                            owner: .mediaFormat,
                            titleID: "mediaFormatTitle",
                            scrollProxy: scrollProxy
                        )
                    },
                    onSelect: { _ in scrollToChartTitle("mediaFormatTitle", scrollProxy: scrollProxy) }
                ) { selectedFormat in
                    vinylSizeDetail(selectedFormat: selectedFormat, scrollProxy: scrollProxy)
                }
            }
        }
    }

    /// Détail par taille de vinyle (12"/10"/7") : n'apparaît que lorsque la part « Vinyles » est
    /// sélectionnée, dans un fondu discret sous le camembert — c'est la façon la plus lisible de
    /// montrer une sous-catégorie sans surcharger le graphique principal d'une 2e couronne en
    /// permanence.
    @ViewBuilder
    private func vinylSizeDetail(selectedFormat: String?, scrollProxy: ScrollViewProxy) -> some View {
        if selectedFormat == ShelfMediaCategory.vinyl12.broadFormatLabel, !viewModel.vinylSizeBreakdown.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Détail par taille")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.appTertiaryText)

                HStack(spacing: 8) {
                    ForEach(viewModel.vinylSizeBreakdown) { entry in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            openMediaFormatSheet(
                                title: entry.category.displayName,
                                items: viewModel.items(forShelfCategory: entry.category),
                                owner: .none,
                                titleID: "mediaFormatTitle",
                                scrollProxy: scrollProxy
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
            .motionTransition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    func mediaFormatColor(for name: String) -> Color {
        // Comparé aux libellés traduits de `ShelfMediaCategory` (mêmes valeurs que les parts).
        switch name {
        case ShelfMediaCategory.vinyl12.broadFormatLabel: return Color.spinlogPink
        case ShelfMediaCategory.cd.broadFormatLabel: return Color.chartColor(preferring: [.blue, .violet, .teal])
        case ShelfMediaCategory.cassette.broadFormatLabel: return Color.chartColor(preferring: [.orange, .yellow, .green])
        default: return Color.chartNeutral
        }
    }

    // MARK: - Camembert : répartition par label

    func labelDistributionSection(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow(title: "Répartition par label", icon: "tag.fill")
                .id("labelTitle")

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
                StatsPieChart(
                    slices: viewModel.labelDistribution.map { PieSlice(name: $0.name, count: $0.count, percentage: $0.percentage) },
                    pie: chartSelection.label,
                    valueLabel: "Occurrences",
                    accessibilityTitle: Text("Répartition par label"),
                    valueText: { String(localized: "\($0) albums") },
                    color: { genreColor(for: $0, index: $1) },
                    countText: { LocalizedStringResource("\($0) albums") },
                    emptyIcon: "tag.fill",
                    totalText: { LocalizedStringResource("\($0) labels") },
                    verticalPadding: 10,
                    onOpen: { name in
                        openMediaFormatSheet(
                            title: name,
                            items: viewModel.items(forLabel: name),
                            owner: .label,
                            titleID: "labelTitle",
                            scrollProxy: scrollProxy
                        )
                    },
                    onSelect: { _ in scrollToChartTitle("labelTitle", scrollProxy: scrollProxy) }
                ) { _ in
                    EmptyView()
                }
            }
        }
    }
}
