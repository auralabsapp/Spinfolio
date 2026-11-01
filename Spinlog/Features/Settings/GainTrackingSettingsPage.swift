import SwiftUI

/// Page « Suivi de plus-value » de Réglages : l'offre Premium et l'aide « Comment ça fonctionne ? »,
/// la devise par défaut et la saisie rapide après un ajout, puis, facultativement, les champs
/// personnalisés Discogs associés au prix d'achat et à l'état du disque. Prix et état sont gardés
/// dans l'app (`CopyDetailsStore`) : les champs Discogs ne servent qu'à reprendre des valeurs déjà
/// saisies sur le site et à y renvoyer les nouvelles. Seul le calcul de la plus-value est Premium.
struct GainTrackingSettingsPage: View {
    @State private var authManager = DiscogsAuthManager.shared
    @State private var premiumStore = PremiumStore.shared

    @State private var availableCollectionFields: [CollectionField] = []
    @State private var purchasePriceFieldId: Int?
    @State private var mediaConditionFieldId: Int?
    @State private var defaultCurrency: String = "EUR"
    @State private var offersCompletionAfterAdd = true
    @State private var sendsToDiscogs = false

    var body: some View {
        SettingsSubPage(title: "Suivi de plus-value") {
            gainTrackingSection
            localDataSection
            discogsFieldsSection
        }
        .task { await loadSettings() }
        // Champs et devise modifiés depuis un autre appareil (iCloud) : ces `@State` ne sont chargés
        // qu'une fois à l'apparition et ne suivraient pas.
        .onReceive(NotificationCenter.default.publisher(for: .collectionPreferencesChanged)) { _ in
            Task { await loadSettings() }
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
            // Accessible à tous, abonnés ou non : cette aide explique quoi saisir comme prix
            // d'achat et comme état du disque, que chacun renseigne même sans Premium.
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

    /// Réglages gratuits : devise par défaut (saisie et conversion) et saisie rapide après un ajout.
    /// Le prix d'achat et l'état servent aussi à la cote, elle aussi gratuite.
    @ViewBuilder
    private var localDataSection: some View {
        if authManager.isAuthenticated {
            Section {
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

                Toggle(isOn: Binding(
                    get: { offersCompletionAfterAdd },
                    set: { newValue in
                        offersCompletionAfterAdd = newValue
                        if let user = authManager.username {
                            CollectionPreferencesStore.setOffersCompletionAfterAdd(newValue, for: user)
                        }
                    }
                )) {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "square.and.pencil", backgroundColor: .green)
                        Text("Proposer après un ajout")
                    }
                }
                .tint(Color.spinlogPink)
            } header: {
                SectionEyebrow(title: "Prix d'achat et état", icon: "tag.fill")
            } footer: {
                Text("Le prix d'achat et l'état du disque se saisissent dans « Mon exemplaire » et sont enregistrés dans l'app, sur cet appareil. « Proposer après un ajout » ouvre leur saisie juste après l'ajout d'un album.")
            }
        }
    }

    // MARK: - Champs Discogs (facultatif)

    /// Association facultative à des champs personnalisés Discogs : les valeurs déjà présentes sur
    /// ces champs sont reprises dans l'app, et chaque prix ou état saisi y est aussi écrit. Sans
    /// champ associé, rien n'est envoyé à Discogs.
    @ViewBuilder
    private var discogsFieldsSection: some View {
        if authManager.isAuthenticated {
            Section {
                fieldPicker(
                    title: "Champ Discogs du prix d'achat",
                    icon: "tag.fill",
                    color: .green,
                    selection: purchasePriceFieldId,
                    onSelect: { fieldId in
                        purchasePriceFieldId = fieldId
                        if let user = authManager.username {
                            CollectionPreferencesStore.setPurchasePriceFieldId(fieldId, for: user)
                        }
                    }
                )
                fieldPicker(
                    title: "Champ Discogs de l'état du disque",
                    icon: "opticaldisc.fill",
                    color: .purple,
                    selection: mediaConditionFieldId,
                    onSelect: { fieldId in
                        mediaConditionFieldId = fieldId
                        if let user = authManager.username {
                            CollectionPreferencesStore.setMediaConditionFieldId(fieldId, for: user)
                        }
                    }
                )

                Toggle(isOn: Binding(
                    get: { sendsToDiscogs },
                    set: { newValue in
                        sendsToDiscogs = newValue
                        if let user = authManager.username {
                            CollectionPreferencesStore.setSendsCopyDetailsToDiscogs(newValue, for: user)
                        }
                    }
                )) {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "arrow.up.circle.fill", backgroundColor: .teal)
                        Text("Envoyer vers Discogs")
                    }
                }
                .tint(Color.spinlogPink)
                .disabled(purchasePriceFieldId == nil && mediaConditionFieldId == nil)

                if sendsToDiscogs && (purchasePriceFieldId != nil || mediaConditionFieldId != nil) {
                    NavigationLink(value: SettingsDestination.copyDetailsDiscogsSend) {
                        HStack(spacing: 14) {
                            SettingsIcon(systemName: "icloud.and.arrow.up.fill", backgroundColor: .indigo)
                            Text("Envoyer tout vers Discogs")
                        }
                    }
                }

                NavigationLink(value: SettingsDestination.copyDetailsImport) {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "square.and.arrow.down.fill", backgroundColor: .orange)
                        Text("Importer depuis Discogs")
                    }
                }
            } header: {
                SectionEyebrow(title: "Champs Discogs (facultatif)", icon: "arrow.triangle.2.circlepath")
            } footer: {
                Text("Associe des champs personnalisés de ton compte Discogs pour reprendre les valeurs qu'ils contiennent. Avec « Envoyer vers Discogs », chaque prix ou état que tu saisis ensuite y est aussi écrit ; « Envoyer tout vers Discogs » y renvoie ceux déjà enregistrés dans l'app. Sans cette option, rien n'est envoyé à Discogs.")
            }
        }
    }

    private func fieldPicker(
        title: LocalizedStringKey,
        icon: String,
        color: Color,
        selection: Int?,
        onSelect: @escaping (Int?) -> Void
    ) -> some View {
        Picker(selection: Binding(
            get: { selection ?? -1 },
            set: { onSelect($0 == -1 ? nil : $0) }
        )) {
            Text("Aucun").tag(-1)
            ForEach(availableCollectionFields) { field in
                Text(field.name).tag(field.id)
            }
        } label: {
            HStack(spacing: 14) {
                SettingsIcon(systemName: icon, backgroundColor: color)
                Text(title)
            }
        }
        .pickerStyle(.menu)
        .tint(Color.spinlogPink)
    }

    // MARK: - Chargement

    /// Relit les réglages du compte et charge les champs personnalisés Discogs à proposer. Aucune
    /// association automatique : un champ n'est lié que par choix de l'utilisateur.
    private func loadSettings() async {
        guard let username = authManager.username else { return }
        defaultCurrency = CollectionPreferencesStore.defaultCurrency(for: username)
        purchasePriceFieldId = CollectionPreferencesStore.purchasePriceFieldId(for: username)
        mediaConditionFieldId = CollectionPreferencesStore.mediaConditionFieldId(for: username)
        offersCompletionAfterAdd = CollectionPreferencesStore.offersCompletionAfterAdd(for: username)
        sendsToDiscogs = CollectionPreferencesStore.sendsCopyDetailsToDiscogs(for: username)

        guard NetworkMonitor.shared.isConnected else { return }
        let fields = await CollectionFieldsService.fields(username: username, credentials: authManager.credentials)
        guard !fields.isEmpty else { return }
        availableCollectionFields = fields
    }
}
