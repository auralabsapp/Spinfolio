import SwiftUI

/// Aperçu marketplace en lecture seule : statistiques de vente et estimation de prix par état.
/// Discogs n'expose pas d'endpoint public pour lister les annonces individuelles d'une release
/// (juste l'inventaire d'un vendeur précis, ou une annonce dont on connaît déjà l'identifiant) :
/// on renvoie donc vers le site pour consulter les annonces en détail plutôt que d'en inventer.
struct MarketplaceSheet: View {
    let releaseId: Int
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = MarketplaceSheetViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Marketplace")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        SheetCloseButton()
                    }
                }
                .task { await viewModel.load(releaseId: releaseId) }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView("Indisponible", systemImage: "tag.slash", description: Text(errorMessage))
        } else {
            List {
                Section {
                    if let stats = viewModel.stats {
                        LabeledContent("En vente") {
                            Text("\(stats.numForSale ?? 0)")
                        }
                        if let lowestPrice = stats.lowestPrice {
                            LabeledContent("Prix le plus bas") {
                                Text(lowestPrice.formatted)
                            }
                        }
                        if stats.blockedFromSale == true {
                            Text("Cette release ne peut pas être vendue actuellement.")
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }

                if !viewModel.suggestions.isEmpty {
                    Section("Estimation par état") {
                        ForEach(viewModel.orderedSuggestions, id: \.0) { condition, price in
                            LabeledContent(condition) {
                                Text(price.formatted)
                            }
                        }
                    }
                } else if !DiscogsAuthManager.shared.isAuthenticated {
                    Section {
                        Text("Connecte-toi à Discogs pour voir une estimation de prix par état.")
                            .font(.caption)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }

                Section {
                    Link(destination: DiscogsConstants.websiteURL.appendingPathComponent("sell/release/\(releaseId)")) {
                        Label("Voir les annonces sur Discogs.com", systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
    }
}
