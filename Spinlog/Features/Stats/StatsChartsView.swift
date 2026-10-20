import SwiftUI
import Charts

/// Camemberts (genre, support physique, label) de l'onglet Stats — extrait de StatsView.swift
/// (2176 lignes à l'origine) pour isoler cette responsabilité. Voir le commentaire sur
/// `StatsView` : les membres sont `internal` (pas `private`) précisément pour permettre ce
/// découpage en extensions à travers plusieurs fichiers.
extension StatsView {
    // MARK: - Graphique Camembert : Répartition par Genre

    @ViewBuilder
    var topArtistsSection: some View {
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
                        .accessibilityHidden(true)
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
                                .chartSelectionAccessibility(
                                    label: Text("Classement des artistes"),
                                    entries: viewModel.topArtistsByCollectionCount.map {
                                        ChartAccessibilityEntry(id: $0.name, name: $0.name, valueText: String(localized: "\($0.count) disques"))
                                    }
                                ) { artistName in
                                    selectedArtistData = ArtistReleasesSheetData(artist: artistName, items: viewModel.items(forArtist: artistName))
                                }
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

    var genreDistributionSection: some View {
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
                            // Pas de `.cornerRadius` : son tracé (`Path.roundedSector`) plantait Charts
                            // (NaN converti en Int) quand le graphique était redimensionné à une
                            // taille quasi nulle, par ex. à l'apparition animée du mini-lecteur.
                            .foregroundStyle(genreColor(for: entry.name, index: index))
                            .opacity(selectedGenreName == nil || isSelected ? 1.0 : 0.35)
                            .accessibilityHidden(true)
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
                                    .chartSelectionAccessibility(
                                        label: Text("Répartition par genre"),
                                        entries: viewModel.genreDistribution.map {
                                            ChartAccessibilityEntry(id: $0.name, name: $0.name, valueText: String(localized: "\($0.count) disques"))
                                        }
                                    ) { genre in
                                        selectedGenreName = genre
                                        selectedGenreData = GenreReleasesSheetData(genre: genre, items: viewModel.items(forGenre: genre))
                                    }
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
                                    .font(.statHeadlineNumber)
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
                                            .font(.inlineIcon)
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
                                                title: "\(selectedGenreName) · \(entry.name)",
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

    func handlePieChartTap(at location: CGPoint, in size: CGSize) {
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

    func updateSelectionFromAngle(_ angle: Double) {
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

    func genreColor(for name: String, index: Int) -> Color {
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

    var mediaFormatDistributionSection: some View {
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
                            // Pas de `.cornerRadius` : son tracé (`Path.roundedSector`) plantait Charts
                            // (NaN converti en Int) quand le graphique était redimensionné à une
                            // taille quasi nulle, par ex. à l'apparition animée du mini-lecteur.
                            .foregroundStyle(mediaFormatColor(for: entry.name))
                            .opacity(selectedMediaFormatName == nil || isSelected ? 1.0 : 0.35)
                            .accessibilityHidden(true)
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
                                    .chartSelectionAccessibility(
                                        label: Text("Répartition par support"),
                                        entries: viewModel.mediaFormatDistribution.map {
                                            ChartAccessibilityEntry(id: $0.name, name: $0.name, valueText: String(localized: "\($0.count) exemplaires"))
                                        }
                                    ) { format in
                                        selectedMediaFormatName = format
                                        selectedMediaFormatData = MediaFormatReleasesSheetData(title: format, items: viewModel.items(forMediaFormat: format))
                                    }
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
                                    .font(.statHeadlineNumber)
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
                                            .font(.inlineIcon)
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

    func handleMediaFormatPieTap(at location: CGPoint, in size: CGSize) {
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

    func updateMediaFormatSelectionFromAngle(_ angle: Double) {
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

    func mediaFormatColor(for name: String) -> Color {
        // Comparé aux libellés traduits de `ShelfMediaCategory` (mêmes valeurs que les parts).
        switch name {
        case ShelfMediaCategory.vinyl12.broadFormatLabel: return Color.spinlogPink
        case ShelfMediaCategory.cd.broadFormatLabel: return Color(red: 0.28, green: 0.52, blue: 0.95)
        case ShelfMediaCategory.cassette.broadFormatLabel: return Color(red: 0.98, green: 0.58, blue: 0.22)
        default: return Color(white: 0.55)
        }
    }

    // MARK: - Graphique Camembert : Répartition par Label

    var labelDistributionSection: some View {
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
                            // Pas de `.cornerRadius` : son tracé (`Path.roundedSector`) plantait Charts
                            // (NaN converti en Int) quand le graphique était redimensionné à une
                            // taille quasi nulle, par ex. à l'apparition animée du mini-lecteur.
                            .foregroundStyle(genreColor(for: entry.name, index: index))
                            .opacity(selectedLabelName == nil || isSelected ? 1.0 : 0.35)
                            .accessibilityHidden(true)
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
                                    .chartSelectionAccessibility(
                                        label: Text("Répartition par label"),
                                        entries: viewModel.labelDistribution.map {
                                            ChartAccessibilityEntry(id: $0.name, name: $0.name, valueText: String(localized: "\($0.count) disques"))
                                        }
                                    ) { label in
                                        selectedLabelName = label
                                        selectedMediaFormatData = MediaFormatReleasesSheetData(title: label, items: viewModel.items(forLabel: label))
                                    }
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
                                    .font(.statHeadlineNumber)
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
                                            .font(.inlineIcon)
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

    func handleLabelPieTap(at location: CGPoint, in size: CGSize) {
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

    func updateLabelSelectionFromAngle(_ angle: Double) {
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

}
