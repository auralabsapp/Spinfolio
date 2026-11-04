import SwiftUI

struct ArtistCount: Equatable {
    let name: String
    let count: Int
}

/// Classement des artistes par nombre de disques : barres horizontales fines avec le nom de l'artiste
/// au-dessus de chacune, en liste défilant verticalement au-delà de 5 lignes, limité aux 10 premiers artistes. Toucher une barre met l'artiste en avant (les autres s'estompent) et
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
    /// Largeur disponible pour les barres, mesurée une fois pour toute la liste (pas de
    /// `GeometryReader` par ligne).
    @State private var availableWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Hauteur d'une ligne : le nom au-dessus de la barre, sans empiéter sur la ligne précédente.
    /// Nombre maximal d'artistes proposés : le haut du classement, pas les 1 000 suivants.
    static let maxEntries = 10
    private static let rowHeight: CGFloat = 50
    private static let barHeight: CGFloat = 14
    /// Place réservée à droite de la barre la plus longue pour son nombre d'albums.
    private static let countLabelWidth: CGFloat = 36

    var body: some View {
        let revealed = isRevealed || reduceMotion
        let selectedArtist = selection.topArtist
        let shown = Array(entries.prefix(Self.maxEntries))
        let maxCount = max(1, shown.map(\.count).max() ?? 1)
        let visibleHeight = min(CGFloat(shown.count), 5) * Self.rowHeight + 6
        let maxBarWidth = max(0, availableWidth - Self.countLabelWidth)

        // Liste paresseuse plutôt qu'un `Chart` : sur une grosse collection (plus de 1 000
        // artistes), le graphique dessinait toutes les barres et leurs étiquettes d'un bloc, sur
        // des dizaines de milliers de points de haut, et le défilement de l'onglet saccadait.
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(shown, id: \.name) { entry in
                    row(
                        entry,
                        barWidth: revealed ? maxBarWidth * CGFloat(entry.count) / CGFloat(maxCount) : 0,
                        isDimmed: selectedArtist != nil && selectedArtist != entry.name,
                        selectedArtist: selectedArtist
                    )
                }
            }
            .padding(.vertical, 3)
            .animation(.easeOut(duration: 0.8), value: revealed)
        }
        .frame(height: visibleHeight)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .onGeometryChange(for: CGFloat.self) { @Sendable proxy in proxy.size.width } action: { availableWidth = $0 }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .appleMusicGroupedCard()
        .onScrollVisibilityChange(threshold: 0.3) { visible in
            if visible { isRevealed = true }
        }
    }

    private func row(_ entry: ArtistCount, barWidth: CGFloat, isDimmed: Bool, selectedArtist: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.name)
                .font(.caption)
                .foregroundStyle(Color.appSecondaryText)
                .lineLimit(1)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(barStyle(isDimmed: isDimmed))
                    .frame(width: barWidth, height: Self.barHeight)
                Text("\(entry.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.appSecondaryText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Second toucher sur la barre déjà ouverte : on referme tout.
            if selectedArtist == entry.name && selection.artistData != nil {
                selection.deselectArtist()
            } else {
                onSelect(entry.name)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(entry.name))
        .accessibilityValue(Text("\(entry.count) albums"))
        .accessibilityAddTraits(selectedArtist == entry.name ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(Text("Affiche les albums de cet artiste."))
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
