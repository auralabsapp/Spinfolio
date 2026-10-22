import SwiftUI

/// Position du seuil d'alerte par rapport au prix le plus bas actuellement en vente.
nonisolated struct PriceAlertGaugeModel: Equatable {
    let target: Double
    let lowest: Double?

    /// L'alerte se déclencherait tout de suite : une offre est déjà au seuil ou en dessous.
    var isReached: Bool {
        guard let lowest else { return false }
        return lowest <= target
    }

    /// Écart entre le prix le plus bas et le seuil (0 si le seuil est déjà atteint).
    var gap: Double? {
        lowest.map { max(0, $0 - target) }
    }

    /// Baisse de prix nécessaire, rapportée au prix le plus bas actuel.
    var gapPercent: Double? {
        guard let lowest, lowest > 0, let gap else { return nil }
        return gap / lowest
    }

    /// Borne haute de l'échelle : 25 % au-dessus du plus grand des deux repères, pour que ni l'un
    /// ni l'autre ne touche le bord.
    var upperBound: Double {
        max(max(target, lowest ?? 0) * 1.25, 1)
    }

    /// Position d'un montant sur l'échelle, de 0 (à gauche) à 1 (à droite).
    func position(of value: Double) -> Double {
        min(max(value / upperBound, 0), 1)
    }
}

/// Jauge « mon seuil / prix le plus bas en ligne » : la zone rose à gauche du seuil est celle où une
/// offre déclencherait l'alerte.
struct PriceAlertGauge: View {
    let model: PriceAlertGaugeModel
    let currency: String

    private static let trackHeight: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let width = geo.size.width
                let targetX = width * model.position(of: model.target)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [Color.spinlogPink.opacity(0.55), Color.spinlogPink], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(targetX, Self.trackHeight))

                    marker(color: Color.spinlogPink)
                        .position(x: targetX, y: Self.trackHeight / 2)

                    if let lowest = model.lowest {
                        marker(color: model.isReached ? Color.gainPositive : Color.primary)
                            .position(x: width * model.position(of: lowest), y: Self.trackHeight / 2)
                    }
                }
                .frame(height: Self.trackHeight)
            }
            .frame(height: 18)

            HStack {
                legend(color: Color.spinlogPink, text: "Mon seuil")
                Spacer()
                if model.lowest != nil {
                    legend(color: model.isReached ? Color.gainPositive : Color.primary, text: "Annonce la moins chère")
                }
            }

            statusText
                .font(.footnote.weight(.semibold))
                .foregroundStyle(model.isReached ? Color.gainPositive : Color.appSecondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusText: some View {
        if model.lowest == nil {
            Text("Aucune annonce en vente pour l'instant.")
        } else if model.isReached {
            Text("Seuil atteint : une annonce est déjà à ce prix ou moins.")
        } else if let gap = model.gap {
            let amount = gap.formatted(.currency(code: currency))
            if let percent = model.gapPercent {
                Text("Il manque \(amount) (\(percent.formatted(.percent.precision(.fractionLength(0))))) pour atteindre ton seuil.")
            } else {
                Text("Il manque \(amount) pour atteindre ton seuil.")
            }
        }
    }

    private func marker(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(Color.appBackground, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }

    private func legend(color: Color, text: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appSecondaryText)
        }
    }
}

#Preview("Seuil non atteint, dans une liste") {
    List {
        Section {
            PriceAlertGauge(model: PriceAlertGaugeModel(target: 25, lowest: 40), currency: "EUR")
                .listRowBackground(Color.clear)
        }
        Section {
            PriceAlertGauge(model: PriceAlertGaugeModel(target: 45, lowest: 40), currency: "EUR")
                .listRowBackground(Color.clear)
        }
    }
    .listStyle(.plain)
}
