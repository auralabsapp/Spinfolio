import SwiftUI
import Charts

enum YearHistogramKind {
    case originalYears
    case additions
}

struct YearCount: Equatable {
    let year: Int
    let count: Int
}

/// Histogramme vertical d'une barre par année (ou décennie) : sorties originales ou exemplaires
/// ajoutés. Défile latéralement au-delà de `maxVisibleBars` barres.
struct YearHistogramChart: View {
    let kind: YearHistogramKind
    let entries: [YearCount]
    let maxVisibleBars: Int
    let selection: StatsChartSelection
    let valueLabel: LocalizedStringKey
    let accessibilityTitle: Text
    let valueText: (Int) -> String
    /// Toucher (ou action VoiceOver) sur une barre non sélectionnée : année, texte de la barre.
    let onSelect: (Int, String) -> Void

    var body: some View {
        // Lue ici, dans le corps (suivi d'observation), puis passée aux marques : le contenu du
        // `Chart` est évalué par Charts, hors de ce suivi.
        let selectedYear = kind == .originalYears ? selection.originalYear : selection.additionsYear
        let totalBars = entries.count
        let hasScroll = totalBars > maxVisibleBars
        let maxCount = entries.map(\.count).max() ?? 0

        GeometryReader { containerGeo in
            let availableWidth = containerGeo.size.width
            let stepWidth = availableWidth / CGFloat(maxVisibleBars)
            let chartWidth = hasScroll ? stepWidth * CGFloat(totalBars) : availableWidth

            ScrollView(.horizontal, showsIndicators: false) {
                Chart(entries, id: \.year) { entry in
                    BarMark(
                        x: .value("Année", String(entry.year)),
                        y: .value(valueLabel, entry.count)
                    )
                    .foregroundStyle(barStyle(isDimmed: selectedYear != nil && selectedYear != String(entry.year)))
                    .cornerRadius(5)
                    .accessibilityHidden(true)
                    .annotation(position: .top, spacing: 4) {
                        annotationBadge(isSelected: selectedYear == String(entry.year), count: entry.count)
                    }
                }
                .chartYScale(domain: 0...(max(1, Int(Double(maxCount) * 1.25))))
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .chartSelectionAccessibility(
                                label: accessibilityTitle,
                                entries: entries.map {
                                    ChartAccessibilityEntry(id: String($0.year), name: String($0.year), valueText: valueText($0.count))
                                }
                            ) { yearText in
                                if let year = Int(yearText) {
                                    onSelect(year, yearText)
                                }
                            }
                            .onTapGesture { location in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let relativeX = location.x - geometry[plotFrame].origin.x
                                guard let tappedYear: String = proxy.value(atX: relativeX),
                                      let entry = entries.first(where: { String($0.year) == tappedYear }) else { return }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()

                                // Second toucher sur la barre déjà ouverte : on referme tout.
                                if selectedYear == tappedYear && selection.yearData != nil {
                                    selection.deselect()
                                } else {
                                    onSelect(entry.year, tappedYear)
                                }
                            }
                    }
                }
                .frame(width: chartWidth, height: 160)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .frame(height: 160)
    }

    private func barStyle(isDimmed: Bool) -> LinearGradient {
        isDimmed ? Color.spinlogChartDimmedGradient : Color.spinlogChartGradient
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
}
