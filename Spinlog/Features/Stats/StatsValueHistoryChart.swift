import SwiftUI
import Charts

/// Courbe d'évolution de la cote : la fourchette et la médiane se dessinent de gauche à droite la
/// première fois que le graphique est visible à l'écran (comme les autres graphiques de Stats).
/// Sans « Réduire les animations », elle s'affiche directement.
struct StatsValueHistoryChart: View {
    let points: [(date: Date, low: Double, median: Double, high: Double)]

    @State private var isRevealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let revealed = isRevealed || reduceMotion

        Chart(Array(points.enumerated()), id: \.offset) { _, point in
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
        // Un masque qui s'élargit depuis la gauche : plus simple et plus fluide que d'animer les
        // données, et il ne change ni les axes ni la mise en page du graphique.
        .mask(alignment: .leading) {
            Rectangle()
                .scaleEffect(x: revealed ? 1 : 0.001, anchor: .leading)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 1.0), value: revealed)
        .onScrollVisibilityChange(threshold: 0.3) { visible in
            if visible { isRevealed = true }
        }
        // Résumé lu par VoiceOver à la place des marques du graphique, comme les autres
        // graphiques de Stats : médiane au premier et au dernier point, puis la tendance.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Évolution de la cote")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: Text {
        guard let first = points.first, let last = points.last else { return Text(verbatim: "") }
        let start = first.median.formatted(.number.precision(.fractionLength(0...2)))
        let end = last.median.formatted(.number.precision(.fractionLength(0...2)))
        let startDate = first.date.formatted(date: .abbreviated, time: .omitted)
        let endDate = last.date.formatted(date: .abbreviated, time: .omitted)
        let values = Text("Médiane de \(start) le \(startDate) à \(end) le \(endDate)")
        guard first.median > 0 else { return values }
        let change = (last.median - first.median) / first.median
        let percent = abs(change).formatted(.percent.precision(.fractionLength(0)))
        if change > 0.005 {
            return Text("\(values), en hausse de \(percent)")
        } else if change < -0.005 {
            return Text("\(values), en baisse de \(percent)")
        }
        return Text("\(values), stable")
    }
}
