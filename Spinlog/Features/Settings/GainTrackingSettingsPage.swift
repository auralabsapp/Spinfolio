import SwiftUI

/// Page « Suivi de plus-value » de Réglages : l'offre Premium et l'aide « Comment ça fonctionne ? »,
/// puis les champs Discogs qui alimentent le calcul (prix d'achat, état du disque) et la devise. Les
/// champs sont accessibles à tous : seul le calcul de la plus-value est Premium. C'est ici
/// qu'arrive la pastille « Utilisé pour la plus-value » de « Mon exemplaire », avec la ligne du champ
/// concerné mise en évidence.
struct GainTrackingSettingsPage: View {
    @State private var authManager = DiscogsAuthManager.shared
    @State private var premiumStore = PremiumStore.shared
    @State private var tabCoordinator = TabNavigationCoordinator.shared

    /// Ligne « Prix d'achat » ou « Champ état du disque » mise en évidence à l'arrivée depuis « Mon exemplaire ».
    @State private var highlightedSettingsField: SettingsFieldHighlight?
    @State private var availableCollectionFields: [CollectionField] = []
    @State private var purchasePriceFieldId: Int?
    @State private var mediaConditionFieldId: Int?
    @State private var defaultCurrency: String = "EUR"

    var body: some View {
        ScrollViewReader { proxy in
            SettingsSubPage(title: "Suivi de plus-value") {
                gainTrackingSection
                purchasePriceSection
                    .id("purchasePriceSection")
            }
            // `initial: true` : à la toute première visite, la demande de mise en évidence a été émise
            // avant que cette page n'existe (le changement du déclencheur passerait inaperçu) ; elle
            // est donc aussi lue à l'apparition.
            .onChange(of: tabCoordinator.scrollToPurchasePriceSectionTrigger, initial: true) { _, _ in
                guard let field = tabCoordinator.consumePendingSettingsFieldHighlight() else { return }
                Task { @MainActor in
                    // Attendre la fin de la fermeture de la feuille et du changement d'onglet, centrer
                    // la section, puis mettre la ligne en évidence 2 s.
                    try? await Task.sleep(for: .milliseconds(450))
                    withAnimation { proxy.scrollTo("purchasePriceSection", anchor: UnitPoint(x: 0.5, y: 0.2)) }
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(.settingsRowHighlight) { highlightedSettingsField = field }
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.settingsRowHighlight) { highlightedSettingsField = nil }
                }
            }
        }
        .task { await loadPurchasePriceSettings() }
        // Champs et devise modifiés depuis un autre appareil (iCloud) : ces `@State` ne sont chargés
        // qu'une fois à l'apparition et ne suivraient pas.
        .onReceive(NotificationCenter.default.publisher(for: .collectionPreferencesChanged)) { _ in
            Task { await loadPurchasePriceSettings() }
        }
    }

    // MARK: - Suivi de plus-value (Premium)

    @ViewBuilder
    private var gainTrackingSection: some View {
        Section {
            if !premiumStore.isPremium {
                PremiumLockedCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Suivi de plus-value",
                    message: "Passe premium pour comparer ton investissement à la cote actuelle et suivre ta plus-value."
                )
            }
            // Accessible à tous, abonnés ou non : cette aide explique quoi saisir dans le prix
            // d'achat et l'état de la pochette, des champs que chacun remplit même sans Premium.
            NavigationLink(value: SettingsDestination.purchasePriceHelp) {
                HStack(spacing: 14) {
                    SettingsIcon(systemName: "questionmark.circle.fill", backgroundColor: .mint)
                    Text("Comment ça fonctionne ?")
                }
            }
        } header: {
            SectionEyebrow(title: "Suivi de plus-value", icon: "chart.line.uptrend.xyaxis", isPremiumFeature: true)
        }
    }

    // MARK: - Prix d'achat et état (gratuit)

    /// Fond de ligne par défaut, teinté le temps de la mise en évidence d'un champ, comme la règle de rangement.
    private func settingsFieldRowBackground(_ field: SettingsFieldHighlight) -> some View {
        ZStack {
            Color(uiColor: .secondarySystemGroupedBackground)
            // Même teinte que le nom et la pastille du champ dans « Mon exemplaire ».
            field.tint.opacity(highlightedSettingsField == field ? 0.2 : 0)
        }
    }

    /// Réglages gratuits : le prix d'achat est un champ personnalisé Discogs que chacun peut
    /// remplir (ici comme sur discogs.com), et l'état et la devise servent aussi à la cote, elle
    /// aussi gratuite. Seul le calcul de la plus-value est Premium.
    @ViewBuilder
    private var purchasePriceSection: some View {
        if authManager.isAuthenticated {
            Section {
                Picker(selection: Binding(
                    get: { purchasePriceFieldId ?? -1 },
                    set: { newValue in
                        let fieldId = newValue == -1 ? nil : newValue
                        purchasePriceFieldId = fieldId
                        if let user = authManager.username {
                            CollectionPreferencesStore.setPurchasePriceFieldId(fieldId, for: user)
                        }
                    }
                )) {
                    Text("Aucun").tag(-1)
                    ForEach(availableCollectionFields) { field in
                        Text(field.name).tag(field.id)
                    }
                } label: {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "tag.fill", backgroundColor: .green)
                        Text("Champ prix d'achat")
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.spinlogPink)
                .listRowBackground(settingsFieldRowBackground(.purchasePrice))

                Picker(selection: Binding(
                    get: { mediaConditionFieldId ?? -1 },
                    set: { newValue in
                        let fieldId = newValue == -1 ? nil : newValue
                        mediaConditionFieldId = fieldId
                        if let user = authManager.username {
                            CollectionPreferencesStore.setMediaConditionFieldId(fieldId, for: user)
                        }
                    }
                )) {
                    Text("Aucun").tag(-1)
                    ForEach(availableCollectionFields) { field in
                        Text(field.name).tag(field.id)
                    }
                } label: {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "opticaldisc.fill", backgroundColor: .purple)
                        Text("Champ état du disque")
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.spinlogPink)
                .listRowBackground(settingsFieldRowBackground(.mediaCondition))

                Picker(selection: Binding(
                    get: { defaultCurrency },
                    set: { newValue in
                        defaultCurrency = newValue
                        if let user = authManager.username {
                            CollectionPreferencesStore.setDefaultCurrency(newValue, for: user)
                        }
                    }
                )) {
                    ForEach(PurchasePriceParser.supportedCurrencies, id: \.self) { code in
                        Text(code).tag(code)
                    }
                } label: {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "eurosign.circle.fill", backgroundColor: .blue)
                        Text("Devise par défaut")
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.spinlogPink)
            } header: {
                SectionEyebrow(title: "Prix d'achat et état", icon: "tag.fill")
            } footer: {
                Text("Associe les champs personnalisés Discogs correspondants à ton prix d'achat et à l'état de conservation pour alimenter le suivi de valeur.")
            }
        }
    }

    // MARK: - Chargement

    /// Charge les champs personnalisés Discogs et, pour chaque champ pas déjà configuré (prix
    /// d'achat, état du disque), tente une détection automatique par mots-clés insensible à la
    /// casse et aux accents.
    private func loadPurchasePriceSettings() async {
        guard let username = authManager.username else { return }
        defaultCurrency = CollectionPreferencesStore.defaultCurrency(for: username)
        purchasePriceFieldId = CollectionPreferencesStore.purchasePriceFieldId(for: username)
        mediaConditionFieldId = CollectionPreferencesStore.mediaConditionFieldId(for: username)

        guard NetworkMonitor.shared.isConnected else { return }
        let fields = await ReleaseActions.fetchCollectionFields(username: username, credentials: authManager.credentials)
        guard !fields.isEmpty else { return }
        availableCollectionFields = fields

        if purchasePriceFieldId == nil {
            let keywords = ["prix d'achat", "prix", "purchase price", "price", "bought for", "cost"]
            if let detected = fields.first(where: { field in
                let normalized = field.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                return keywords.contains { normalized.contains($0) }
            }) {
                purchasePriceFieldId = detected.id
                CollectionPreferencesStore.setPurchasePriceFieldId(detected.id, for: username)
            }
        }

        if mediaConditionFieldId == nil {
            // Discogs fournit aussi par défaut "Sleeve Condition" (état de la pochette) : on
            // l'exclut explicitement pour ne pas la confondre avec l'état du média.
            if let detected = fields.first(where: { field in
                let normalized = field.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                guard !normalized.contains("sleeve"), !normalized.contains("pochette") else { return false }
                return normalized.contains("media condition") || normalized.contains("etat du media") || normalized.contains("etat du disque")
            }) {
                mediaConditionFieldId = detected.id
                CollectionPreferencesStore.setMediaConditionFieldId(detected.id, for: username)
            }
        }
    }
}
