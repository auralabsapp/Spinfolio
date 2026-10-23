import SwiftUI
import Charts

/// Une part d'un camembert de l'onglet Stats (genre, support, label).
struct PieSlice: Identifiable, Equatable {
    let name: String
    let count: Int
    let percentage: Double
    var id: String { name }
}

/// Camembert de répartition (genre, support, label) : anneau interactif, détail de la part
/// sélectionnée au centre, et contenu optionnel de détail sous l'anneau.
///
/// Les trois camemberts étaient trois copies du même code avec chacun ses `@State` dans
/// `StatsView` ; la sélection vit désormais dans un `StatsPieSelection` observable que seul ce
/// composant lit (voir `StatsChartSelection`).
///
/// Toucher une part la sélectionne (`onSelect`, qui fait défiler le titre du graphique en haut de
/// l'écran même sans feuille) ; la toucher de nouveau, toucher le centre ou « Voir » ouvre la
/// feuille de ses disques (`onOpen`) ; toucher à l'extérieur désélectionne.
struct StatsPieChart<Detail: View>: View {
    let slices: [PieSlice]
    @Bindable var pie: StatsPieSelection
    let valueLabel: LocalizedStringKey
    let accessibilityTitle: Text
    let valueText: (Int) -> String
    let color: (String, Int) -> Color
    let countText: (Int) -> LocalizedStringResource
    let emptyIcon: String
    let totalText: (Int) -> LocalizedStringResource
    /// Marge verticale de la carte (le camembert du support n'en a pas : son détail par taille
    /// de vinyle porte déjà la sienne).
    let verticalPadding: CGFloat
    let onOpen: (String) -> Void
    let onSelect: (String) -> Void
    /// Contenu sous l'anneau pour la part sélectionnée (`nil` si aucune).
    @ViewBuilder let detail: (String?) -> Detail

    private static var spring: Animation { .spring(response: 0.35, dampingFraction: 0.85) }

    /// L'anneau apparaît en grossissant la première fois qu'il est visible à l'écran.
    @State private var isRevealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Lue ici, dans le corps (suivi d'observation), puis passée aux marques : le contenu du
        // `Chart` est évalué par Charts, hors de ce suivi.
        let selectedName = pie.name

        VStack(spacing: 0) {
            ZStack {
                Chart(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    let isSelected = selectedName == slice.name
                    SectorMark(
                        angle: .value(valueLabel, slice.count),
                        innerRadius: .ratio(isSelected ? 0.58 : 0.62),
                        outerRadius: .ratio(isSelected ? 1.0 : 0.94),
                        angularInset: 1.5
                    )
                    // Pas de `.cornerRadius` : son tracé (`Path.roundedSector`) plantait Charts
                    // (NaN converti en Int) quand le graphique était redimensionné à une
                    // taille quasi nulle, par ex. à l'apparition animée du mini-lecteur.
                    .foregroundStyle(color(slice.name, index))
                    .opacity(selectedName == nil || isSelected ? 1.0 : 0.35)
                    .accessibilityHidden(true)
                }
                .chartAngleSelection(value: $pie.angle)
                .frame(height: 230)
                .opacity(isRevealed || reduceMotion ? 1 : 0)
                .scaleEffect(isRevealed || reduceMotion ? 1 : 0.88)
                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: isRevealed)
                .chartOverlay { _ in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                handleTap(at: location, in: geo.size)
                            }
                            .chartSelectionAccessibility(
                                label: accessibilityTitle,
                                entries: slices.map {
                                    ChartAccessibilityEntry(id: $0.name, name: $0.name, valueText: valueText($0.count))
                                }
                            ) { name in
                                pie.name = name
                                onOpen(name)
                            }
                    }
                }

                center(selectedName: selectedName)
            }
            .padding(.vertical, 14)

            // Animé à part (ressort) : sans cela le ressort s'appliquait à tout, anneau compris,
            // et l'estompage des autres parts n'était plus instantané.
            detail(selectedName)
                .animation(Self.spring, value: selectedName)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, verticalPadding)
        .appleMusicGroupedCard()
        .onScrollVisibilityChange(threshold: 0.3) { visible in
            if visible { isRevealed = true }
        }
        .onChange(of: pie.angle) { _, newAngle in
            if let newAngle {
                select(fromAngle: newAngle)
            }
        }
    }

    // MARK: - Centre de l'anneau

    @ViewBuilder
    private func center(selectedName: String?) -> some View {
        VStack(spacing: 4) {
            if let selected = slices.first(where: { $0.name == selectedName }) {
                let tint = color(selected.name, slices.firstIndex(where: { $0.name == selected.name }) ?? 0)

                Text(selected.name)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text((selected.percentage / 100).formatted(.percent.precision(.fractionLength(0))))
                    .font(.statHeadlineNumber)
                    .foregroundStyle(tint)

                Text(countText(selected.count))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.appSecondaryText)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onOpen(selected.name)
                } label: {
                    HStack(spacing: 3) {
                        Text("Voir")
                            .font(.caption2.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.inlineIcon)
                    }
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            } else {
                Image(systemName: emptyIcon)
                    .font(.title)
                    .foregroundStyle(Color.spinlogPink)
                    .padding(.bottom, 2)

                Text(totalText(slices.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Toucher une portion")
                    .font(.caption2)
                    .foregroundStyle(Color.appSecondaryText)
            }
        }
        .padding(.horizontal, 30)
        .allowsHitTesting(selectedName != nil)
        .animation(Self.spring, value: selectedName)
    }

    // MARK: - Interaction

    private func handleTap(at location: CGPoint, in size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        let maxRadius = min(size.width, size.height) / 2
        let innerRadius = maxRadius * 0.55

        // Centre de l'anneau : ouvre la feuille de la part sélectionnée.
        if distance < innerRadius {
            if let current = pie.name {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onOpen(current)
            }
            return
        }

        // En dehors de l'anneau : désélectionne.
        guard distance <= maxRadius * 1.15 else {
            if pie.name != nil {
                withAnimation(.chartSelection) { pie.name = nil }
            }
            return
        }

        var angle = atan2(dx, -dy)
        if angle < 0 {
            angle += 2 * .pi
        }

        let total = Double(slices.map(\.count).reduce(0, +))
        guard total > 0 else { return }
        let targetValue = (angle / (2 * .pi)) * total

        var accumulated: Double = 0
        for slice in slices {
            accumulated += Double(slice.count)
            if targetValue <= accumulated {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if pie.name == slice.name {
                    onOpen(slice.name)
                } else {
                    withAnimation(.chartSelection) { pie.name = slice.name }
                    onSelect(slice.name)
                }
                return
            }
        }
    }

    /// Sélection par la position angulaire fournie par `chartAngleSelection`.
    private func select(fromAngle angle: Double) {
        var accumulated: Double = 0
        for slice in slices {
            accumulated += Double(slice.count)
            if angle <= accumulated {
                if pie.name != slice.name {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.chartSelection) { pie.name = slice.name }
                    onSelect(slice.name)
                }
                break
            }
        }
    }
}
