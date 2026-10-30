import SwiftUI

struct WantlistAlertSheet: View {
    let item: WantlistItem

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = WantlistAlertViewModel()
    /// Montant saisi et symbole de devise : grands chiffres de la carte, qui suivent malgré tout la
    /// taille de texte choisie par l'utilisateur (au lieu de tailles fixes).
    @ScaledMetric(relativeTo: .largeTitle) private var targetPriceSize: CGFloat = 44
    @ScaledMetric(relativeTo: .title) private var currencySymbolSize: CGFloat = 28

    @State private var showPermissionAlert = false
    @State private var showingDeleteConfirmation = false
    /// Page à ouvrir : présentée via `fullScreenCover(item:)`, jamais un `Bool` avec une URL
    /// séparée, qui peut ouvrir une page vide (voir `SafariViewRequest`).
    @State private var safariRequest: SafariViewRequest?
    @FocusState private var isTargetPriceFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Sélection du champ de prix : permet de ramener le curseur en fin de montant à chaque prise de
    /// focus (voir `placeCursorAtEnd`).
    @State private var priceSelection: TextSelection?
    /// Couleur moyenne de la pochette, pour teinter le fond (voir `releaseTintedBackground`).
    @State private var coverTint: UIColor?
    /// Passe à vrai une seule fois, juste après la fin du chargement du marché : déclenche l'entrée
    /// en séquence des tuiles, de la jauge et des pastilles (jamais réarmé).
    @State private var marketRevealed = false
    /// Montant affiché pendant le « défilement » des chiffres après l'application d'une pastille ;
    /// `nil` hors de ce court moment (le champ de saisie reprend alors la main).
    @State private var rollingPrice: String?
    /// Léger gonflement du grand montant quand une pastille l'applique.
    @State private var isPriceBumped = false
    /// Lueur verte brève quand le seuil saisi rejoint l'annonce la moins chère.
    @State private var showsReachedFlash = false

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

    private static let thresholdSectionID = "thresholdSection"

    private func dismissKeyboard() {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows }
            .flatMap { $0 }
            .first { $0.isKeyWindow }?
            .endEditing(true)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                albumHeaderSection
                alertSettingsSection
                marketOverviewSection
                if viewModel.isLoading || !viewModel.suggestions.isEmpty {
                    priceSuggestionsSection
                }
                viewListingsSection
            }
            // Au focus du prix maximum, le titre « Mon seuil d'alerte » remonte en haut de l'écran :
            // champ, jauge et pastilles restent ainsi visibles au-dessus du clavier. Le léger délai
            // laisse le clavier apparaître, sans quoi le `Form` n'a pas encore la marge pour défiler.
            .onChange(of: isTargetPriceFocused) { _, isFocused in
                guard isFocused else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard isTargetPriceFocused else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                        // Pas `.top` : le haut du défilement passe sous la barre de navigation, qui
                        // masquerait le titre de section situé juste au-dessus de cette ligne.
                        proxy.scrollTo(Self.thresholdSectionID, anchor: UnitPoint(x: 0.5, y: 0.24))
                    }
                }
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
                    // « Terminé » : « OK » est le bouton qui enregistre l'alerte, en haut de la feuille.
                    Button("Terminé") { isTargetPriceFocused = false }
                        .fontWeight(.semibold)
                        .tint(Color.spinlogPink)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") {
                        Task {
                            let saved = await viewModel.saveAlert(for: item)
                            if saved {
                                dismiss()
                            } else {
                                showPermissionAlert = true
                            }
                        }
                    }
                    .accessibilityLabel("Enregistrer l'alerte")
                    .bold()
                    .disabled((viewModel.targetPrice ?? 0) <= 0 || viewModel.isSaving)
                }
            }
            .onChange(of: viewModel.isLoading) { _, isLoading in
                guard !isLoading, !marketRevealed else { return }
                // Légèrement différé : l'état de départ (masqué) doit d'abord être affiché.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(40))
                    marketRevealed = true
                }
            }
            .onChange(of: isTargetReached) { old, new in
                guard old == false, new == true else { return }
                celebrateReachedTarget()
            }
            .task {
                viewModel.setupInitialValues(for: item)
                await viewModel.loadMarketData(for: item)
            }
            .fullScreenCover(item: $safariRequest) { request in
                SafariView(url: request.url)
            }
            .confirmationDialog("Supprimer cette alerte ?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Supprimer cette alerte", role: .destructive) {
                    viewModel.deleteAlert(for: item)
                    dismiss()
                }
            } message: {
                Text("Tu ne seras plus prévenu pour cet album.")
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
                    alertBell: existingAlert.map { $0.isTriggered ? .triggered : .active } ?? AlertBellState.none,
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
                        .shelfEntrance(isVisible: marketRevealed, offset: CGSize(width: 0, height: 18), delay: 0)
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
                        .shelfEntrance(isVisible: marketRevealed, offset: CGSize(width: 0, height: 18), delay: 0.12)
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

    private func marketTile(
        title: LocalizedStringKey,
        value: Text,
        icon: String,
        highlighted: Bool = false,
        action: (() -> Void)? = nil
    ) -> some View {
        MarketTile(title: title, value: value, icon: icon, highlighted: highlighted, action: action)
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
                    ForEach(Array(viewModel.suggestions.enumerated()), id: \.element.condition) { index, suggestion in
                        priceChip(
                            title: suggestion.condition,
                            price: suggestion.price,
                            isSelected: isTargetPrice(suggestion.price)
                        )
                        // Pastilles en cascade, après les tuiles et la jauge.
                        .shelfEntrance(
                            isVisible: marketRevealed,
                            offset: CGSize(width: 28, height: 0),
                            delay: 0.3 + 0.07 * Double(index)
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
            footer: Text("L'alerte se déclenche dès qu'un exemplaire à ce prix ou moins est détecté, lors d'une vérification (à l'ouverture de l'app ou occasionnellement en arrière-plan) — pas nécessairement en temps réel. L'état exact de l'album et les frais de port seront à vérifier sur l'annonce Discogs.")
        ) {
            VStack(spacing: 4) {
                // Cible du défilement au focus (voir `scrollTo`) : une ligne courte s'aligne de façon
                // prévisible, contrairement à toute la section, trop haute pour se caler correctement.
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
                        .font(.system(size: currencySymbolSize, weight: .semibold, design: .rounded))
                        .hidden()
                        .accessibilityHidden(true)

                    ZStack {
                        TextField("0,00", text: $viewModel.targetPriceString, selection: $priceSelection)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .font(.system(size: targetPriceSize, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.spinlogPink)
                            .minimumScaleFactor(0.6)
                            .focused($isTargetPriceFocused)
                            .accessibilityLabel("Prix maximum")
                            // Masqué le temps du défilement des chiffres, qu'un `TextField` ne sait pas animer.
                            .opacity(rollingPrice == nil ? 1 : 0)
                            .allowsHitTesting(rollingPrice == nil)

                        if let rollingPrice {
                            Text(rollingPrice)
                                .font(.system(size: targetPriceSize, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Color.spinlogPink)
                                .minimumScaleFactor(0.6)
                                .contentTransition(.numericText(value: Double(rollingPrice.replacingOccurrences(of: ",", with: ".")) ?? 0))
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: 190)
                    .scaleEffect(isPriceBumped ? 1.07 : 1)

                    Text(viewModel.currencySymbol)
                        .font(.system(size: currencySymbolSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.appSecondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.spinlogPink.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Halo rose qui respire tant que le champ a le focus : on voit où l'on tape.
            .background {
                if isTargetPriceFocused {
                    BreathingGlow(cornerRadius: 16, blurRadius: 12, minOpacity: 0.10, maxOpacity: 0.32)
                        .transition(.opacity)
                }
            }
            // Lueur verte brève quand le seuil rejoint l'annonce la moins chère.
            .background {
                if showsReachedFlash {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.gainPositive)
                        .opacity(0.35)
                        .blur(radius: 14)
                        .padding(-4)
                        .transition(.opacity)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.spinlogPink.opacity(isTargetPriceFocused ? 0.55 : 0), lineWidth: 1.5)
            )
            .animation(.easeInOut(duration: 0.25), value: isTargetPriceFocused)
            .animation(.easeInOut(duration: 0.3), value: showsReachedFlash)
            .contentShape(Rectangle())
            .onTapGesture { isTargetPriceFocused = true }
            // Curseur toujours à la fin du montant, où que l'on touche : pour corriger un prix déjà
            // saisi, on efface ou on complète à partir de la fin.
            .onChange(of: isTargetPriceFocused) { _, isFocused in
                if isFocused { placeCursorAtEnd() }
            }
            .id(Self.thresholdSectionID)
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
                    currency: viewModel.currency,
                    isRevealed: marketRevealed
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

            // Sous le champ du seuil, pour ne pas avoir à défiler jusqu'en bas de la feuille.
            if existingAlert != nil {
                DeleteAlertButton { showingDeleteConfirmation = true }
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

    /// Pastille de prix (voir `PriceChip`) : applique ce montant comme seuil.
    private func priceChip(title: String, price: Double, isSelected: Bool) -> some View {
        PriceChip(title: title, price: price, currency: viewModel.currency, isSelected: isSelected) {
            applyPrice(price)
        }
    }

    /// Applique un montant venu d'une pastille : les chiffres du grand prix « roulent » de l'ancien
    /// montant au nouveau, avec un léger gonflement. Avec « Réduire les animations », il change d'un coup.
    private func applyPrice(_ price: Double) {
        UISelectionFeedbackGenerator().selectionChanged()
        guard !reduceMotion else {
            viewModel.applySuggestion(price: price)
            return
        }
        let previous = viewModel.targetPriceString.isEmpty ? "0.00" : viewModel.targetPriceString
        rollingPrice = previous
        viewModel.applySuggestion(price: price)
        let updated = viewModel.targetPriceString
        withAnimation(.snappy(duration: 0.55)) {
            rollingPrice = updated
            isPriceBumped = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { isPriceBumped = false }
            try? await Task.sleep(for: .milliseconds(450))
            rollingPrice = nil
        }
    }

    /// `nil` tant que la comparaison n'est pas possible (pas de prix saisi, marché non chargé) ;
    /// sinon vrai si une annonce est déjà au seuil ou en dessous. Sert à détecter le franchissement.
    private var isTargetReached: Bool? {
        guard let target = viewModel.targetPrice, target > 0, !viewModel.isLoading, viewModel.currentStats != nil else { return nil }
        return PriceAlertGaugeModel(target: target, lowest: viewModel.convertedLowestPrice).isReached
    }

    /// Le seuil vient de rejoindre l'annonce la moins chère : retour haptique de succès et lueur verte brève.
    private func celebrateReachedTarget() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        guard !reduceMotion else { return }
        showsReachedFlash = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1300))
            showsReachedFlash = false
        }
    }
}
