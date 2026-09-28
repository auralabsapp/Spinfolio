import SwiftUI
import Charts

struct StatsView: View {
    @State private var viewModel = StatsViewModel()
    @State private var authManager = DiscogsAuthManager.shared

    var body: some View {
        content
            .navigationTitle("Statistiques")
            .task(id: authManager.isAuthenticated) {
                if authManager.isAuthenticated {
                    await viewModel.loadOverview()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if !authManager.isAuthenticated {
            LoginPromptView(message: "Connecte-toi à Discogs pour voir tes statistiques.")
        } else if viewModel.isLoadingOverview {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            ContentUnavailableView("Erreur", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    countersRow
                    recentAdditionsSection
                    histogramSection
                    valuationSection
                }
                .padding()
            }
        }
    }

    private var countersRow: some View {
        HStack(spacing: 12) {
            StatCounterCard(
                title: "Collection",
                value: viewModel.totalCollectionCount.map(String.init) ?? "–",
                systemImage: "square.stack.fill",
                tint: .accentColor
            )
            StatCounterCard(
                title: "Wantlist",
                value: viewModel.totalWantlistCount.map(String.init) ?? "–",
                systemImage: "heart.fill",
                tint: .pink
            )
        }
    }

    @ViewBuilder
    private var recentAdditionsSection: some View {
        if !viewModel.recentAdditions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(title: "Derniers ajouts")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.recentAdditions) { item in
                            NavigationLink(value: SearchDestination.release(item.releaseId, coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    AsyncCoverImage(url: item.basicInformation.coverImage ?? item.basicInformation.thumb, cornerRadius: 8)
                                        .frame(width: 96, height: 96)
                                    Text(item.basicInformation.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                    Text(item.basicInformation.artistNames)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 96)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
    }

    @ViewBuilder
    private var histogramSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Ajouts par année")
            if viewModel.isLoadingHistogram && viewModel.additionsPerYear.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .appleMusicGroupedCard()
            } else if viewModel.additionsPerYear.isEmpty {
                Text("Pas encore assez de données.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .appleMusicGroupedCard()
            } else {
                Chart(viewModel.additionsPerYear, id: \.year) { entry in
                    BarMark(
                        x: .value("Année", String(entry.year)),
                        y: .value("Ajouts", entry.count)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(4)
                }
                .frame(height: 160)
                .padding(12)
                .appleMusicGroupedCard()
            }
        }
    }

    private var valuationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Estimation de la collection")
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(formattedValuation)
                        .font(.title2.bold())
                    Spacer()
                    if viewModel.isValuating {
                        ProgressView()
                    }
                }

                if viewModel.valuationTotal > 0 {
                    ProgressView(value: Double(viewModel.valuationEvaluated), total: Double(viewModel.valuationTotal))
                    Text(viewModel.isValuating
                         ? "\(viewModel.valuationEvaluated) / \(viewModel.valuationTotal) disques évalués…"
                         : "Basé sur le prix le plus bas en vente pour \(viewModel.valuationEvaluated) disques.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appleMusicGroupedCard()
        }
    }

    private var formattedValuation: String {
        guard viewModel.valuationEvaluated > 0, let currency = viewModel.estimatedValueCurrency else {
            return "–"
        }
        return viewModel.estimatedValue.formatted(.currency(code: currency))
    }
}

private struct StatCounterCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.title.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appleMusicGroupedCard()
    }
}

#Preview {
    NavigationStack {
        StatsView()
    }
}
