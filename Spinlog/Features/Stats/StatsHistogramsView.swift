import SwiftUI
import Charts

/// Histogrammes (années originales de sortie, exemplaires ajoutés par année) de l'onglet
/// Stats — extrait de StatsView.swift, voir le commentaire sur `StatsChartsView`.
extension StatsView {
    // MARK: - Sélection d'une année (toucher ou action VoiceOver)

    func selectOriginalYear(_ year: Int, tappedYear: String, scrollProxy: ScrollViewProxy) {
        let granularity = originalYearsGranularity
        // Les autres barres s'estompent tout de suite ; la liste des disques (filtre + tri de
        // toute la collection) n'est calculée qu'ensuite, hors du fil principal, puis la feuille
        // s'ouvre. Avant, ce calcul précédait l'estompage et le retardait sur une grosse collection.
        withAnimation(.chartSelection) {
            chartSelection.originalYear = tappedYear
            chartSelection.additionsYear = nil
        }

        Task { @MainActor in
            let items: [CollectionItem]
            let title: String
            switch granularity {
            case .year:
                items = await viewModel.items(forOriginalYear: year)
                title = String(localized: "Sortis en \(String(year))")
            case .decade:
                items = await viewModel.items(forOriginalDecade: year)
                title = String(localized: "Sortis dans les années \(String(year))")
            }
            // Sélection abandonnée entre-temps (autre barre, bascule de granularité...) : rien à ouvrir.
            guard chartSelection.originalYear == tappedYear else { return }
            chartSelection.yearData = YearReleasesSheetData(
                year: year,
                items: items,
                type: "originalYears",
                title: title
            )

            scrollToChartTitle("originalYearsTitle", scrollProxy: scrollProxy)
        }
    }

    func selectAdditionsYear(_ year: Int, tappedYear: String, scrollProxy: ScrollViewProxy) {
        // Même principe que `selectOriginalYear` : estompage immédiat, calcul ensuite.
        withAnimation(.chartSelection) {
            chartSelection.additionsYear = tappedYear
            chartSelection.originalYear = nil
        }

        Task { @MainActor in
            let items = await viewModel.items(forYear: year)
            guard chartSelection.additionsYear == tappedYear else { return }
            chartSelection.yearData = YearReleasesSheetData(
                year: year,
                items: items,
                type: "additions",
                title: String(localized: "Ajoutés en \(String(year))")
            )

            scrollToChartTitle("additionsTitle", scrollProxy: scrollProxy)
        }
    }

    // MARK: - Histogramme : Années originales de sortie (Master Year)

    @ViewBuilder
    func originalYearsHistogramSection(scrollProxy: ScrollViewProxy) -> some View {
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
                chartSelection.originalYear = nil
                chartSelection.yearData = nil
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
                    YearHistogramChart(
                        kind: .originalYears,
                        entries: currentOriginalYearsDistribution.map { YearCount(year: $0.year, count: $0.count) },
                        maxVisibleBars: maxVisibleBars,
                        selection: chartSelection,
                        valueLabel: "Albums",
                        accessibilityTitle: Text("Sorties originales"),
                        valueText: { String(localized: "\($0) disques") },
                        onSelect: { year, yearText in
                            selectOriginalYear(year, tappedYear: yearText, scrollProxy: scrollProxy)
                        }
                    )

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
    func additionsHistogramSection(scrollProxy: ScrollViewProxy) -> some View {
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
                YearHistogramChart(
                    kind: .additions,
                    entries: viewModel.additionsPerYear.map { YearCount(year: $0.year, count: $0.count) },
                    maxVisibleBars: maxVisibleBars,
                    selection: chartSelection,
                    valueLabel: "Ajouts",
                    accessibilityTitle: Text("Exemplaires ajoutés par année"),
                    valueText: { String(localized: "\($0) exemplaires") },
                    onSelect: { year, yearText in
                        selectAdditionsYear(year, tappedYear: yearText, scrollProxy: scrollProxy)
                    }
                )
                .padding(12)
                .appleMusicGroupedCard()
            }
        }
    }
}
