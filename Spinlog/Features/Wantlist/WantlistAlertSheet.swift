import SwiftUI

struct WantlistAlertSheet: View {
    let item: WantlistItem

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = WantlistAlertViewModel()

    @State private var showPermissionAlert = false
    /// Page à ouvrir : présentée via `fullScreenCover(item:)`, jamais un `Bool` avec une URL
    /// séparée, qui peut ouvrir une page vide (voir `SafariViewRequest`).
    @State private var safariRequest: SafariViewRequest?
    @FocusState private var isTargetPriceFocused: Bool
    /// Sélection du champ de prix : permet de ramener le curseur en fin de montant à chaque prise de
    /// focus (voir `placeCursorAtEnd`).
    @State private var priceSelection: TextSelection?
    /// Couleur moyenne de la pochette, pour teinter le fond (voir `releaseTintedBackground`).
    @State private var coverTint: UIColor?

    private var existingAlert: WantlistAlert? {
        viewModel.existingAlert(for: item)
    }

    private var marketplaceURL: URL {
        DiscogsConstants.websiteURL.appendingPathComponent("sell/release/\(item.id)")
    }

    /// Place le curseur après le dernier caractère du montant. Légèrement différé : le système
    /// positionne lui-même le curseur au point touché juste après la prise de focus, et écraserait
    /// une sélection posée dans la même image.
    private func placeCursorAtEnd() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            guard isTargetPriceFocused else { return }
            priceSelection = TextSelection(insertionPoint: viewModel.targetPriceString.endIndex)
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows }
            .flatMap { $0 }
            .first { $0.isKeyWindow }?
            .endEditing(true)
    }

    var body: some View {
        NavigationStack {
            Form {
                albumHeaderSection
                alertSettingsSection
                marketOverviewSection
                if viewModel.isLoading || !viewModel.suggestions.isEmpty {
                    priceSuggestionsSection
                }
                viewListingsSection
                if existingAlert != nil {
                    deleteSection
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .releaseTintedBackground(coverTint)
            .listRowSeparator(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // Pas de geste « toucher n'importe où ferme le clavier » sur le `Form` : il se déclenchait
            // au relâchement du doigt, y compris pour le toucher qui venait de donner le focus au
            // champ de prix, qui le perdait aussitôt (il fallait s'y reprendre à plusieurs fois).
            // Le clavier se ferme par le bouton « OK » de sa barre, au défilement, ou au glissé.
            // `.scrollDismissesKeyboard` ne se déclenche que si le `Form` défile réellement : sur
            // cette feuille, si le contenu tient déjà dans l'écran (peu de suggestions, pas
            // d'alerte existante…), aucun défilement n'a jamais lieu et ce modificateur ne fait
            // donc jamais rien. Un `DragGesture` dédié détecte le glissé vertical lui-même, qu'il
            // y ait ou non matière à défiler.
            .simultaneousGesture(
                DragGesture(minimumDistance: 10).onChanged { _ in dismissKeyboard() }
            )
            .searchDestinations()
            .navigationTitle("Alerte de prix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Le clavier décimal n'a pas de touche de validation.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { isTargetPriceFocused = false }
                        .fontWeight(.semibold)
                        .tint(Color.spinlogPink)
                }
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
                    .disabled(viewModel.targetPrice == nil || viewModel.targetPrice! <= 0 || viewModel.isSaving)
                }
            }
            .task {
                viewModel.setupInitialValues(for: item)
                await viewModel.loadMarketData(for: item)
            }
            .fullScreenCover(item: $safariRequest) { request in
                SafariView(url: request.url)
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
            NavigationLink(
                value: SearchDestination.release(item.id, coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb)
            ) {
                ReleaseSheetHeader(
                    coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb,
                    title: item.basicInformation.title,
                    artist: item.basicInformation.artistNames,
                    pills: headerPills,
                    onAverageColorLoaded: { coverTint = $0 }
                )
            }
            .listRowBackground(Color.clear)
        }
    }

    /// Année et format du disque recherché, en pastilles sous le titre.
    private var headerPills: [String] {
        var pills: [String] = []
        if let year = item.basicInformation.year, year > 0 { pills.append(String(year)) }
        if let format = item.basicInformation.formats?.first?.name, !format.isEmpty { pills.append(format) }
        return pills
    }

    private var marketOverviewSection: some View {
        Section(
            header: SectionEyebrow(title: "Offres actuelles en vente", icon: "cart.fill"),
            footer: Text("L'alerte se base sur l'annonce la moins chère en vente, tous états confondus. Les cotes par état ci-dessous sont des estimations tirées de ventes passées : elles peuvent être plus basses sans qu'aucune offre n'existe à ce prix.")
        ) {
            Group {
                if viewModel.isLoading {
                    // Squelette : mêmes deux tuiles que le contenu réel, à la même place.
                    HStack(spacing: 8) {
                        SkeletonBlock(cornerRadius: 14, height: 70)
                        SkeletonBlock(cornerRadius: 14, height: 70)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Chargement du marché Discogs…")
                } else if let stats = viewModel.currentStats {
                    HStack(spacing: 8) {
                        marketTile(
                            title: "En vente",
                            value: Text("\(stats.numForSale ?? 0)"),
                            icon: "cart"
                        )
                        marketTile(
                            title: "Annonce la moins chère",
                            value: viewModel.convertedLowestPrice.map { Text($0.formatted(.currency(code: viewModel.currency))) }
                                ?? Text("Aucune offre"),
                            icon: "tag",
                            highlighted: viewModel.convertedLowestPrice != nil,
                            // Même page Discogs que « Consulter les annonces sur Discogs.com » :
                            // c'est là qu'on voit l'annonce dont il est question.
                            action: { safariRequest = SafariViewRequest(url: marketplaceURL) }
                        )
                    }
                } else {
                    Text("Données de marché non disponibles.")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private func marketTile(
        title: LocalizedStringKey,
        value: Text,
        icon: String,
        highlighted: Bool = false,
        action: (() -> Void)? = nil
    ) -> some View {
        let tile = VStack(spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appSecondaryText)
            value
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(highlighted ? Color.spinlogPink : Color.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if action != nil {
                // Indique que la tuile s'ouvre (comme les lignes qui renvoient vers Discogs).
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.appTertiaryText)
                    .padding(10)
            }
        }

        if let action {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            } label: {
                tile.contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ouvre les annonces sur Discogs.com")
        } else {
            tile.accessibilityElement(children: .combine)
        }
    }

    private var priceSuggestionsSection: some View {
        Section(
            header: SectionEyebrow(title: "Cote moyenne récente par état (Discogs)", icon: "chart.bar.fill"),
            footer: Text("Estimations d'après les ventes passées, pas des offres en cours. Touche un état pour appliquer sa cote comme prix cible.")
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if viewModel.isLoading {
                        // Squelette : pastilles de la taille des vraies (une par état courant).
                        ForEach(0..<4, id: \.self) { _ in
                            SkeletonBlock(cornerRadius: 22, width: 92, height: 50)
                        }
                    }
                    ForEach(viewModel.suggestions, id: \.condition) { suggestion in
                        priceChip(
                            title: suggestion.condition,
                            price: suggestion.price,
                            isSelected: isTargetPrice(suggestion.price)
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    /// Le prix saisi correspond à ce montant, à un centime près (pastille alors mise en évidence).
    private func isTargetPrice(_ price: Double) -> Bool {
        guard let target = viewModel.targetPrice else { return false }
        return abs(target - price) < 0.005
    }

    private var alertSettingsSection: some View {
        Section(
            header: SectionEyebrow(title: "Mon seuil d'alerte", icon: "eurosign.circle.fill", isPremiumFeature: true),
            footer: Text("L'alerte se déclenche dès qu'un exemplaire à ce prix ou moins est détecté, lors d'une vérification (à l'ouverture de l'app ou occasionnellement en arrière-plan) — pas nécessairement en temps réel. L'état exact du disque et les frais de port seront à vérifier sur l'annonce Discogs.")
        ) {
            VStack(spacing: 4) {
                Text("Prix maximum")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appSecondaryText)
                // `TextField(text:)` sur une `String` saisie brute, pas `TextField(value:format:
                // .currency(...))` : ce dernier réinsère le symbole monétaire dans le texte édité
                // à chaque frappe et perd la position du curseur — le 2e chiffre tapé atterrissait
                // après le symbole ("2,00 €5" au lieu de "25,00 €"). Le symbole reste donc un
                // élément à part, affiché en permanence (même champ vide) juste après le champ.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // Symbole invisible, de même largeur que celui de droite : le montant saisi
                    // reste exactement au centre de la carte.
                    Text(viewModel.currencySymbol)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .hidden()
                        .accessibilityHidden(true)

                    TextField("0,00", text: $viewModel.targetPriceString, selection: $priceSelection)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.spinlogPink)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: 190)
                        .focused($isTargetPriceFocused)
                        .accessibilityLabel("Prix maximum")

                    Text(viewModel.currencySymbol)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.appSecondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.spinlogPink.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { isTargetPriceFocused = true }
            // Curseur toujours à la fin du montant, où que l'on touche : pour corriger un prix déjà
            // saisi, on efface ou on complète à partir de la fin.
            .onChange(of: isTargetPriceFocused) { _, isFocused in
                if isFocused { placeCursorAtEnd() }
            }
            .listRowBackground(Color.clear)

            // Juste sous le champ : elle réagit à la saisie et reste visible au-dessus du clavier
            // (placée plus bas, dans « Offres actuelles », elle disparaissait derrière lui).
            if let target = viewModel.targetPrice, target > 0, viewModel.isLoading {
                SkeletonBlock(cornerRadius: 12, height: 74)
                    .listRowBackground(Color.clear)
                    .accessibilityHidden(true)
            } else if let target = viewModel.targetPrice, target > 0, viewModel.currentStats != nil {
                PriceAlertGauge(
                    model: PriceAlertGaugeModel(target: target, lowest: viewModel.convertedLowestPrice),
                    currency: viewModel.currency
                )
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }

            if let current = viewModel.targetPrice, current > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Raccourcis par rapport au prix saisi ci-dessus :")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)

                    HStack(spacing: 8) {
                        priceChip(title: "-10 %", price: current * 0.90, isSelected: false)
                        priceChip(title: "-20 %", price: current * 0.80, isSelected: false)
                        priceChip(title: "-30 %", price: current * 0.70, isSelected: false)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }
        }
    }

    private var viewListingsSection: some View {
        Section {
            Button {
                safariRequest = SafariViewRequest(url: marketplaceURL)
            } label: {
                HStack {
                    Spacer()
                    Label("Consulter les annonces sur Discogs.com", systemImage: "arrow.up.right.square")
                        .font(.subheadline.bold())
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)
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
            .listRowBackground(Color.clear)
        }
    }

    /// Pastille de prix (raccourci en pourcentage ou cote par état) : touche pour l'appliquer comme seuil.
    private func priceChip(title: String, price: Double, isSelected: Bool) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            viewModel.applySuggestion(price: price)
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                Text(price.formatted(.currency(code: viewModel.currency)))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(isSelected ? Color.spinlogPink : Color.spinlogPink.opacity(0.1))
            )
            .overlay(Capsule().strokeBorder(Color.spinlogPink.opacity(isSelected ? 0 : 0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
