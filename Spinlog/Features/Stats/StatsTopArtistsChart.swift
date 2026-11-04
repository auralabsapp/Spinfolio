import SwiftUI
import Charts

struct ArtistCount: Equatable {
    let name: String
    let count: Int
}

/// Classement des artistes par nombre de disques : barres horizontales fines avec le nom de l'artiste
/// au-dessus de chacune, défilant verticalement au-delà de 5 lignes. Toucher une barre met l'artiste en avant (les autres s'estompent) et
/// ouvre sa feuille de disques ; la retoucher referme tout.
///
/// Composant séparé, qui lit lui-même la sélection (voir `StatsChartSelection`) : lue dans le
/// corps de `StatsView`, elle ré-évaluerait tous les graphiques de la page à chaque toucher.
struct TopArtistsChart: View {
    let entries: [ArtistCount]
    let selection: StatsChartSelection
    /// Toucher (ou action VoiceOver) sur une barre non sélectionnée.
    let onSelect: (String) -> Void

    /// Les barres s'allongent depuis zéro la première fois que le graphique est visible à l'écran.
    @State private var isRevealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let revealed = isRevealed || reduceMotion
        // Lue ici, dans le corps (suivi d'observation), puis passée aux marques : le contenu du
        // `Chart` est évalué par Charts, hors de ce suivi.
        let selectedArtist = selection.topArtist
        let maxCount = entries.map(\.count).max() ?? 1
        // Assez haute pour loger le nom au-dessus de la barre, sans empiéter sur la ligne précédente.
        let rowHeight: CGFloat = 50
        let fullHeight = CGFloat(entries.count) * rowHeight + 6
        let visibleHeight = min(fullHeight, rowHeight * 5 + 6)

        ScrollView(.vertical, showsIndicators: true) {
            Chart(entries, id: \.name) { entry in
                BarMark(
                    x: .value("Albums", revealed ? entry.count : 0),
                    y: .value("Artiste", entry.name),
                    height: .fixed(14)
                )
                .foregroundStyle(barStyle(isDimmed: selectedArtist != nil && selectedArtist != entry.name))
                .cornerRadius(4)
                .accessibilityHidden(true)
                // Nom posé explicitement au-dessus de la barre : l'axe Y automatique de Charts
                // place ses étiquettes au bord de la bande, et sa position change d'une version
                // d'iOS à l'autre (étiquettes décalées d'une demi-ligne).
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                        .lineLimit(1)
                        .fixedSize()
                }
                .annotation(position: .trailing) {
                    Text("\(entry.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
            .chartXScale(domain: 0...(max(1, Int(Double(maxCount) * 1.2))))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: fullHeight)
            .animation(.easeOut(duration: 0.8), value: revealed)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let relativeY = location.y - geo[plotFrame].origin.y
                            guard let artistName: String = proxy.value(atY: relativeY) else { return }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()

                            // Second toucher sur la barre déjà ouverte : on referme tout.
                            if selectedArtist == artistName && selection.artistData != nil {
                                selection.deselectArtist()
                            } else {
                                onSelect(artistName)
                            }
                        }
                        .chartSelectionAccessibility(
                            label: Text("Classement des artistes"),
                            entries: entries.map {
                                ChartAccessibilityEntry(id: $0.name, name: $0.name, valueText: String(localized: "\($0.count) albums"))
                            }
                        ) { artistName in
                            onSelect(artistName)
                        }
                }
            }
        }
        .frame(height: visibleHeight)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .appleMusicGroupedCard()
        .onScrollVisibilityChange(threshold: 0.3) { visible in
            if visible { isRevealed = true }
        }
    }

    /// Les barres sont horizontales : le dégradé suit le sens gauche→droite, donc la longueur
    /// réelle de la barre (contrairement aux histogrammes verticaux, haut→bas).
    private func barStyle(isDimmed: Bool) -> LinearGradient {
        LinearGradient(
            colors: isDimmed
                ? [Color.spinlogPink.opacity(0.22), Color.spinlogPink.opacity(0.06)]
                : [Color.chartPinkSoftTop, Color.chartPinkSoftBottom],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
