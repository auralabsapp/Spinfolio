import SwiftUI

/// Maquettes de la section « Statistiques » (voir `GuideVisualView`). Les chiffres sont des
/// exemples affichés en `verbatim` : ce sont des données, pas des libellés à traduire.

// MARK: - Compteurs

struct StatsCountersMock: View {
    var body: some View {
        HStack(spacing: 10) {
            counter("Collection", value: "128", systemImage: "square.stack.fill")
            counter("Wantlist", value: "24", systemImage: "heart.fill")
            counter("Artistes", value: "86", systemImage: "person.2.fill")
        }
        // Tuiles de même hauteur malgré des icônes de hauteurs différentes.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Même habillage que `StatCounterCard` : icône, grand nombre, légende.
    private func counter(_ title: LocalizedStringKey, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.spinlogPink)
            Text(verbatim: value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.appSecondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - Graphiques

struct StatsChartsMock: View {
    private static let bars: [CGFloat] = [22, 36, 28, 50, 40, 58]

    var body: some View {
        HStack(alignment: .bottom, spacing: 28) {
            donut
            histogram
        }
    }

    private var donut: some View {
        ZStack {
            slice(from: 0, to: 0.5, opacity: 1)
            slice(from: 0.52, to: 0.8, opacity: 0.6)
            slice(from: 0.82, to: 0.98, opacity: 0.3)
        }
        .frame(width: 72, height: 72)
    }

    private func slice(from start: Double, to end: Double, opacity: Double) -> some View {
        Circle()
            .trim(from: start, to: end)
            .stroke(Color.spinlogPink.opacity(opacity), style: StrokeStyle(lineWidth: 14, lineCap: .butt))
            .rotationEffect(.degrees(-90))
            .padding(7)
    }

    private var histogram: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(Self.bars.enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.spinlogPink.opacity(index == 3 ? 1 : 0.45))
                    .frame(width: 14, height: height)
            }
        }
        .frame(height: 72, alignment: .bottom)
    }
}

// MARK: - Plus-value

struct GainMock: View {
    var body: some View {
        VStack(spacing: 8) {
            line("Total investi", value: "300 €", color: .primary)
            line("Cote actuelle", value: "420 €", color: .primary)
            line("Plus-value latente", value: "+120 €", color: Color.gainPositive)
        }
    }

    private func line(_ title: LocalizedStringKey, value: String, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.appSecondaryText)
            Spacer(minLength: 0)
            Text(verbatim: value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - Podium

struct PodiumMock: View {
    private static let steps: [(rank: String, height: CGFloat, opacity: Double)] = [
        ("2", 46, 0.6), ("1", 66, 1), ("3", 34, 0.35)
    ]

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Self.steps, id: \.rank) { step in
                VStack(spacing: 4) {
                    if step.rank == "1" {
                        Image(systemName: "waveform")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.spinlogPink)
                    }
                    Text(verbatim: step.rank)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .frame(width: 56, height: step.height)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.spinlogPink.opacity(step.opacity))
                        )
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        GuideVisualView(visual: .statsCounters)
        GuideVisualView(visual: .statsCharts)
        GuideVisualView(visual: .gain)
        GuideVisualView(visual: .podium)
    }
    .padding()
}
