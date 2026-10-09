import SwiftUI

struct WantlistAlertSheet: View {
    let item: WantlistItem

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = WantlistAlertViewModel()

    @State private var showPermissionAlert = false
    @State private var showingSafari = false

    private var existingAlert: WantlistAlert? {
        viewModel.existingAlert(for: item)
    }

    private var marketplaceURL: URL? {
        URL(string: "https://www.discogs.com/sell/release/\(item.id)")
    }

    var body: some View {
        NavigationStack {
            Form {
                albumHeaderSection
                alertSettingsSection
                marketOverviewSection
                if !viewModel.suggestions.isEmpty {
                    priceSuggestionsSection
                }
                viewListingsSection
                if existingAlert != nil {
                    deleteSection
                }
            }
            .navigationTitle("Alerte de prix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") {
                        Task {
                            let saved = await viewModel.saveAlert(for: item)
                            if saved {
                                dismiss()
                            } else {
                                showPermissionAlert = true
                            }
                        }
                    }
                    .bold()
                    .disabled(viewModel.parsedTargetPrice == nil || viewModel.parsedTargetPrice! <= 0 || viewModel.isSaving)
                }
            }
            .task {
                viewModel.setupInitialValues(for: item)
                await viewModel.loadMarketData(for: item)
            }
            .fullScreenCover(isPresented: $showingSafari) {
                if let url = marketplaceURL {
                    SafariView(url: url)
                }
            }
            .alert("Notifications désactivées", isPresented: $showPermissionAlert) {
                Button("Ouvrir Réglages") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Continuer quand même", role: .cancel) {
                    viewModel.saveAlertDirectly(for: item)
                    dismiss()
                }
            } message: {
                Text("Pour recevoir des alertes même lorsque \(AppInfo.name) est fermée, autorise les notifications dans les Réglages de ton iPhone.")
            }
        }
    }

    // MARK: - Sections

    private var albumHeaderSection: some View {
        Section {
            HStack(spacing: 14) {
                AsyncCoverImage(url: item.basicInformation.thumb ?? item.basicInformation.coverImage, cornerRadius: 8)
                    .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.basicInformation.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(item.basicInformation.artistNames)
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondaryText)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var marketOverviewSection: some View {
        Section(header: Text("Offres actuelles en vente")) {
            if viewModel.isLoading {
                HStack {
                    ProgressView()
                        .padding(.trailing, 8)
                    Text("Chargement du marché Discogs…")
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondaryText)
                }
                .padding(.vertical, 4)
            } else if let stats = viewModel.currentStats {
                HStack {
                    Label("En vente actuellement", systemImage: "cart")
                    Spacer()
                    Text("\(stats.numForSale ?? 0) exemplaires")
                        .foregroundStyle(Color.appSecondaryText)
                }

                HStack {
                    Label("Prix le plus bas en ligne", systemImage: "tag")
                    Spacer()
                    if let lowest = viewModel.convertedLowestPrice {
                        Text(lowest.formatted(.currency(code: viewModel.currency)))
                            .bold()
                            .foregroundStyle(Color.spinlogPink)
                    } else {
                        Text("Aucune offre")
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }
            } else {
                Text("Données de marché non disponibles.")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            }
        }
    }

    private var priceSuggestionsSection: some View {
        Section(
            header: Text("Cote moyenne récente par état (Discogs)"),
            footer: Text("Touche un état pour appliquer automatiquement sa cote comme prix cible.")
        ) {
            ForEach(viewModel.suggestions, id: \.condition) { suggestion in
                Button {
                    viewModel.applySuggestion(price: suggestion.price)
                } label: {
                    HStack {
                        Text(suggestion.condition)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(suggestion.price.formatted(.currency(code: viewModel.currency)))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.spinlogPink)
                        Image(systemName: "arrow.up.left.circle")
                            .font(.caption)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var alertSettingsSection: some View {
        Section(
            header: Text("Mon seuil d'alerte"),
            footer: Text("L'alerte se déclenche dès qu'un exemplaire à ce prix ou moins est détecté, lors d'une vérification (à l'ouverture de l'app ou occasionnellement en arrière-plan) — pas nécessairement en temps réel. L'état exact du disque et les frais de port seront à vérifier sur l'annonce Discogs.")
        ) {
            HStack {
                Text("Prix maximum")
                Spacer()
                TextField("Ex: 25.00", text: $viewModel.targetPriceString)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)

                Text(viewModel.currencySymbol)
                    .foregroundStyle(Color.appSecondaryText)
            }

            if let current = viewModel.parsedTargetPrice, current > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Raccourcis par rapport au prix saisi ci-dessus :")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)

                    HStack(spacing: 8) {
                        suggestionButton(label: "-10%", price: current * 0.90)
                        suggestionButton(label: "-20%", price: current * 0.80)
                        suggestionButton(label: "-30%", price: current * 0.70)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var viewListingsSection: some View {
        Section {
            Button {
                showingSafari = true
            } label: {
                HStack {
                    Spacer()
                    Label("Consulter les annonces sur Discogs.com", systemImage: "arrow.up.right.square")
                        .font(.subheadline.bold())
                    Spacer()
                }
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                viewModel.deleteAlert(for: item)
                dismiss()
            } label: {
                HStack {
                    Spacer()
                    Text("Supprimer cette alerte")
                    Spacer()
                }
            }
        }
    }

    private func suggestionButton(label: String, price: Double) -> some View {
        Button {
            viewModel.applySuggestion(price: price)
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.caption.bold())
                Text(price.formatted(.currency(code: viewModel.currency)))
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
