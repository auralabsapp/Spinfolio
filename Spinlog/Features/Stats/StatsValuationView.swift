import SwiftUI
import Charts

/// Estimation de la valeur de la collection (section Premium) de l'onglet Stats — extrait
/// de StatsView.swift, voir le commentaire sur `StatsChartsView`.
extension StatsView {
    @ViewBuilder
    var valuationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Estimation de la collection", icon: "banknote.fill")
            if viewModel.isLoadingValuation {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .appleMusicGroupedCard()
            } else if let value = viewModel.collectionValue {
                VStack(spacing: 0) {
                    valuationRow(title: "Minimum", value: value.minimum)
                    Divider().opacity(0.15).padding(.leading, 14)
                    valuationRow(title: "Médiane", value: value.median)
                    Divider().opacity(0.15).padding(.leading, 14)
                    valuationRow(title: "Maximum", value: value.maximum)
                }
                .padding(.vertical, 4)
                .appleMusicGroupedCard()
                Text("Basée sur l'historique réel des ventes Discogs pour les disques de ta collection.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            } else {
                Text("Estimation indisponible pour le moment.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .appleMusicGroupedCard()
            }
        }
    }

    @ViewBuilder
    var valueHistorySection: some View {
        if viewModel.valueHistoryPoints.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(title: "Évolution de la cote", icon: "chart.line.uptrend.xyaxis")

                Chart(Array(viewModel.valueHistoryPoints.enumerated()), id: \.offset) { _, point in
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
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .appleMusicGroupedCard()

                Text("Zone claire = fourchette basse/haute Discogs ; ligne = valeur médiane.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            }
        }
    }

    @ViewBuilder
    var investedVsValueSection: some View {
        if !premiumStore.isPremium {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(title: "Investi vs Cote actuelle", icon: "arrow.left.arrow.right.circle.fill")
                premiumLockedInvestedCard
            }
        } else if let invested = viewModel.totalInvested, let value = viewModel.collectionValue,
           let median = PurchasePriceParser.parseFormattedDiscogsAmount(value.median) {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(title: "Investi vs Cote actuelle", icon: "arrow.left.arrow.right.circle.fill")

                VStack(spacing: 0) {
                    HStack {
                        Text("Total investi")
                            .font(.subheadline)
                        Spacer()
                        Text(invested.formatted(.currency(code: viewModel.totalInvestedCurrency)))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider().opacity(0.15).padding(.leading, 14)

                    HStack {
                        Text("Cote actuelle")
                            .font(.subheadline)
                        Spacer()
                        Text(value.median)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.spinlogPink)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider().opacity(0.15).padding(.leading, 14)

                    let gain = median.amount - invested
                    let percent = invested > 0 ? (gain / invested) : 0
                    HStack {
                        Text("Plus-value latente")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(gain >= 0 ? "+" : "")\(gain.formatted(.currency(code: median.currency).precision(.fractionLength(0)))) (\(percent.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))))")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(gain >= 0 ? Color.gainPositive : Color.gainNegative)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .appleMusicGroupedCard()

                Text("Le total investi ne compte que les exemplaires dont le prix d'achat est renseigné.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            }
        }
    }

    var premiumLockedInvestedCard: some View {
        PremiumLockedCard(
            icon: "arrow.left.arrow.right.circle.fill",
            title: "Suivi de cote",
            message: "Passe premium pour comparer ton investissement à la cote actuelle et suivre ta plus-value."
        )
    }

    func valuationRow(title: LocalizedStringResource, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.spinlogPink)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
