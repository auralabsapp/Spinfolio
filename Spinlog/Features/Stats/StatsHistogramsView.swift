import SwiftUI
import Charts

/// Histogrammes (années originales de sortie, exemplaires ajoutés par année) de l'onglet
/// Stats — extrait de StatsView.swift, voir le commentaire sur `StatsChartsView`.
extension StatsView {
    // MARK: - Sélection d'une année (toucher ou action VoiceOver)

    func selectOriginalYear(_ year: Int, tappedYear: String, scrollProxy: ScrollViewProxy) {
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

    func selectAdditionsYear(_ year: Int, tappedYear: String, scrollProxy: ScrollViewProxy) {
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
                                .accessibilityHidden(true)
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
                                        .chartSelectionAccessibility(
                                            label: Text("Sorties originales"),
                                            entries: currentOriginalYearsDistribution.map {
                                                ChartAccessibilityEntry(id: String($0.year), name: String($0.year), valueText: String(localized: "\($0.count) disques"))
                                            }
                                        ) { yearText in
                                            if let year = Int(yearText) {
                                                selectOriginalYear(year, tappedYear: yearText, scrollProxy: scrollProxy)
                                            }
                                        }
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
                                                    selectOriginalYear(year, tappedYear: tappedYear, scrollProxy: scrollProxy)
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
                            .accessibilityHidden(true)
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
                                    .chartSelectionAccessibility(
                                        label: Text("Exemplaires ajoutés par année"),
                                        entries: viewModel.additionsPerYear.map {
                                            ChartAccessibilityEntry(id: String($0.year), name: String($0.year), valueText: String(localized: "\($0.count) exemplaires"))
                                        }
                                    ) { yearText in
                                        if let year = Int(yearText) {
                                            selectAdditionsYear(year, tappedYear: yearText, scrollProxy: scrollProxy)
                                        }
                                    }
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
                                                selectAdditionsYear(year, tappedYear: tappedYear, scrollProxy: scrollProxy)
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
    var topArtistBarGradient: LinearGradient {
        LinearGradient(
            colors: [Color.chartPinkSoftTop, Color.chartPinkSoftBottom],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    func originalBarStyle(for year: Int) -> LinearGradient {
        if selectedOriginalYear == nil || selectedOriginalYear == String(year) {
            return Color.spinlogChartGradient
        } else {
            return Color.spinlogChartDimmedGradient
        }
    }

    func additionsBarStyle(for year: Int) -> LinearGradient {
        if selectedAdditionsYear == nil || selectedAdditionsYear == String(year) {
            return Color.spinlogChartGradient
        } else {
            return Color.spinlogChartDimmedGradient
        }
    }

    @ViewBuilder
    func annotationBadge(isSelected: Bool, count: Int) -> some View {
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

}
