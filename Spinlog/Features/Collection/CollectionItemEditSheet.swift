import SwiftUI

/// Édition des tags et des champs personnalisés Discogs (créés par l'utilisateur dans ses
/// réglages Discogs : état de la pochette, notes libres, etc.) pour un exemplaire de la collection.
/// La note (rating) n'est pas éditée ici : elle est globale à la release (partagée par Discogs
/// entre tous les exemplaires) et se gère depuis la carte "Ma note de la release" de la fiche release.
struct CollectionItemEditSheet: View {
    let item: CollectionItem
    let folders: [CollectionFolder]
    @State private var fields: [CollectionField]
    /// Appelé après un enregistrement réussi, avec la note et les valeurs de champs à jour,
    /// pour que l'appelant (liste de collection ou fiche release) rafraîchisse son propre état.
    var onSaved: (Int, [CollectionFieldValue]) -> Void = { _, _ in }
    /// Appelé dès la sélection d'un nouveau dossier (pas groupé avec "Enregistrer" : Discogs
    /// traite le déplacement comme une action indépendante des champs personnalisés).
    var onFolderChanged: (CollectionItem, Int) -> Void = { _, _ in }
    var onDelete: (() async -> Void)? = nil
    /// Échec d'un enregistrement lancé à la fermeture de la feuille : l'alerte de la feuille
    /// n'existe plus, l'appelant affiche donc le message sur son propre écran (sinon l'échec
    /// passait inaperçu et la saisie était perdue sans que l'utilisateur le sache).
    var onSaveFailedAfterDismiss: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var fieldValues: [Int: String]
    @State private var savedFieldValues: [Int: String]
    @State private var savingFieldIds: Set<Int> = []
    @State private var justSavedFieldIds: Set<Int> = []
    @State private var selectedFolderId: Int
    /// Couleur moyenne de la pochette, pour teinter le fond (voir `releaseTintedBackground`).
    @State private var coverTint: UIColor?
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false
    @State private var safariRequest: SafariViewRequest?

    // MARK: - Plus-value de l'exemplaire
    /// Instance dédiée à la seule lecture de la cote marketplace (`refreshMarketEstimateIfNeeded`),
    /// sans rapport avec les dossiers/champs déjà gérés par cette feuille : pas de coût particulier
    /// à la créer ici, ses dépendances (compte, réseau, cache local) sont toutes des singletons.
    @State private var actions = ReleaseActions()
    @State private var purchasePriceInDisplayCurrency: Double?
    @State private var marketEstimateInDisplayCurrency: Double?
    /// Date de la cote si elle a plus de 6 h (servie hors ligne), voir `MarketEstimate`.
    @State private var marketEstimateStaleSince: Date?
    @State private var isLoadingGain = false
    @State private var showingMarketplaceSheet = false

    init(
        item: CollectionItem,
        fields: [CollectionField],
        folders: [CollectionFolder] = [],
        onSaved: @escaping (Int, [CollectionFieldValue]) -> Void = { _, _ in },
        onFolderChanged: @escaping (CollectionItem, Int) -> Void = { _, _ in },
        onDelete: (() async -> Void)? = nil,
        onSaveFailedAfterDismiss: @escaping (String) -> Void = { _ in }
    ) {
        self.item = item
        self.folders = folders
        self._fields = State(initialValue: fields)
        self.onSaved = onSaved
        self.onFolderChanged = onFolderChanged
        self.onDelete = onDelete
        self.onSaveFailedAfterDismiss = onSaveFailedAfterDismiss
        _selectedFolderId = State(initialValue: item.folderId)
        var initialValues: [Int: String] = [:]
        for note in item.notes {
            initialValues[note.fieldId] = note.value
        }
        for field in fields {
            if initialValues[field.id] == nil {
                initialValues[field.id] = item.value(forFieldId: field.id)
            }
        }
        _fieldValues = State(initialValue: initialValues)
        _savedFieldValues = State(initialValue: initialValues)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !networkMonitor.isConnected {
                        // Si `fields` est vide, il n'y a de toute façon rien d'éditable dans
                        // cette fiche hors ligne (les tags ne sont jamais synchronisés avec
                        // Discogs) : annoncer une synchro différée serait trompeur.
                        OfflineBannerView(customMessage: fields.isEmpty
                            ? String(localized: "Certaines informations ne sont pas disponibles hors ligne")
                            : String(localized: "Les modifications seront synchronisées avec Discogs au retour du réseau")
                        )
                    }

                    discRow

                    VStack(alignment: .leading, spacing: 10) {
                        SectionEyebrow(title: "Dossier Discogs", icon: "folder.fill")

                        if folders.isEmpty {
                            Text(networkMonitor.isConnected ? "Aucun dossier disponible" : "Dossiers indisponibles hors ligne")
                                .font(.subheadline)
                                .foregroundStyle(Color.appSecondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .appleMusicGroupedCard()
                        } else {
                            HStack {
                                Text("Dossier")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Picker("", selection: $selectedFolderId) {
                                    // « All » est une vue agrégée de Discogs, pas un dossier où ranger un
                                    // exemplaire (même règle que le menu de déplacement de la Collection).
                                    ForEach(folders.filter { $0.id != DiscogsConstants.allFolderId }) { folder in
                                        Text(folder.name).tag(folder.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .tint(Color.appSecondaryText)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .appleMusicGroupedCard()
                        }
                    }

                    gainSection

                    VStack(alignment: .leading, spacing: 10) {
                        SectionEyebrow(title: "Tags de l'exemplaire", icon: "tag.fill")
                        TagsEditor(instanceId: item.instanceId, releaseId: item.releaseId)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .appleMusicGroupedCard()

                        Text("Les tags sont des données locales à l'application et ne sont pas sauvegardés sur Discogs.")
                            .font(.footnote)
                            .foregroundStyle(Color.appSecondaryText)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionEyebrow(title: "Champs personnalisés Discogs", icon: "list.bullet.rectangle.portrait")

                        if fields.isEmpty {
                            // Sans réseau, `fields` est vide faute de pouvoir interroger Discogs
                            // (le cache de `fetchCollectionFields` est seulement en mémoire, voir
                            // `ReleaseActions.swift`) : ne pas laisser croire qu'aucun champ
                            // personnalisé n'est configuré, alors qu'on ne peut simplement pas le savoir.
                            Text(networkMonitor.isConnected ? "Aucun champ personnalisé configuré" : "Champs personnalisés indisponibles hors ligne")
                                .font(.subheadline)
                                .foregroundStyle(Color.appSecondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .appleMusicGroupedCard()
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                                    let isDirty = (fieldValues[field.id] ?? "") != (savedFieldValues[field.id] ?? "")
                                    let isSaving = savingFieldIds.contains(field.id)
                                    let justSaved = justSavedFieldIds.contains(field.id)

                                    CollectionFieldControl(
                                        field: field,
                                        value: binding(for: field),
                                        isDirty: isDirty,
                                        isSaving: isSaving,
                                        justSaved: justSaved,
                                        onSave: {
                                            Task {
                                                await saveField(field, value: fieldValues[field.id] ?? "")
                                            }
                                        },
                                        gainRole: gainFieldRole(for: field),
                                        onGainFieldTap: gainFieldRole(for: field).map { role in
                                            { openGainFieldSetting(role) }
                                        }
                                    )
                                    if index < fields.count - 1 {
                                        Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 14)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .appleMusicGroupedCard()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Contrairement aux tags qui sont des données locales, ces champs sont synchronisés avec ton compte Discogs. La validation s'effectue automatiquement avec le bouton « OK » du clavier, en touchant en dehors du champ, ou avec la coche qui apparaît à côté du champ modifié.")
                                .font(.footnote)
                                .foregroundStyle(Color.appSecondaryText)

                            Button {
                                safariRequest = SafariViewRequest(url: DiscogsConstants.websiteURL.appendingPathComponent("settings/collection"))
                            } label: {
                                Label("Gérer les champs sur discogs.com", systemImage: "arrow.up.right")
                                    .font(.footnote.weight(.medium))
                            }
                        }
                    }

                    if onDelete != nil {
                        Button {
                            showingDeleteConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                if isDeleting {
                                    ProgressView()
                                } else {
                                    Label("Supprimer cet exemplaire", systemImage: "trash")
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.red)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .appleMusicGroupedCard()
                        .disabled(!savingFieldIds.isEmpty || isDeleting)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
            )
            .releaseTintedBackground(coverTint)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Titre posé en `.principal` plutôt que via `.navigationTitle` : ce placement est
                // toujours centré par le système, qu'il y ait ou non un élément à gauche — pas
                // besoin d'un faux bouton côté opposé pour compenser (qui, même invisible, affichait
                // quand même la pastille en verre que la barre d'outils applique à tout élément).
                ToolbarItem(placement: .principal) {
                    Text("Mon exemplaire")
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.semibold)
                    .tint(Color.spinlogPink)
                }
            }
            .onChange(of: selectedFolderId) { _, newFolderId in
                guard newFolderId != item.folderId else { return }
                onFolderChanged(item, newFolderId)
            }
            .onDisappear {
                for field in fields {
                    let current = fieldValues[field.id] ?? ""
                    if current != (savedFieldValues[field.id] ?? "") {
                        Task {
                            await saveField(field, value: current, afterDismiss: true)
                        }
                    }
                }
            }
            .errorAlert(message: $errorMessage, fallbackMessage: "Une erreur est survenue lors de l'enregistrement sur Discogs.")
            .confirmationDialog(
                "Supprimer cet exemplaire ?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Supprimer l'exemplaire", role: .destructive) {
                    Task {
                        isDeleting = true
                        await onDelete?()
                        isDeleting = false
                        dismiss()
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Cet exemplaire sera définitivement supprimé de ta collection Discogs.")
            }
            .sheet(isPresented: $showingMarketplaceSheet) {
                MarketplaceSheet(releaseId: item.releaseId)
            }
            .sheet(item: $safariRequest) { request in
                SafariView(url: request.url)
            }
            .task {
                if fields.isEmpty, let username = DiscogsAuthManager.shared.username {
                    let fetched = await CollectionFieldsService.fields(username: username, credentials: DiscogsAuthManager.shared.credentials)
                    if !fetched.isEmpty {
                        fields = fetched
                        for field in fetched {
                            if fieldValues[field.id] == nil {
                                let val = item.value(forFieldId: field.id)
                                fieldValues[field.id] = val
                                savedFieldValues[field.id] = val
                            }
                        }
                    }
                }
            }
        }
    }

    /// Valeur brute d'un champ : d'abord l'état local déjà chargé dans la feuille (reflète un
    /// prix d'achat tout juste modifié plus bas, sans fermer/rouvrir), sinon l'exemplaire tel que
    /// chargé à l'ouverture.
    private func rawFieldValue(_ fieldId: Int) -> String {
        fieldValues[fieldId] ?? item.value(forFieldId: fieldId)
    }

    private var purchasePriceFieldId: Int? {
        guard let username = DiscogsAuthManager.shared.username else { return nil }
        return CollectionPreferencesStore.purchasePriceFieldId(for: username)
    }

    /// Même logique que `MyItemCard.declaredCondition` sur la fiche release : le champ "état du
    /// disque" choisi dans les réglages (auto-détecté ou sélectionné manuellement), sinon une
    /// détection par mots-clés parmi les champs déjà chargés. Affine l'estimation de cote
    /// (sinon `refreshMarketEstimateIfNeeded` retombe sur une moyenne).
    private var declaredCondition: String? {
        if let username = DiscogsAuthManager.shared.username,
           let configuredFieldId = CollectionPreferencesStore.mediaConditionFieldId(for: username) {
            let value = rawFieldValue(configuredFieldId)
            return value.isEmpty ? nil : value
        }
        guard let field = fields.first(where: { field in
            let normalized = field.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            guard !normalized.contains("sleeve"), !normalized.contains("pochette") else { return false }
            return normalized.contains("media condition") || normalized.contains("etat du media") || normalized.contains("etat du disque")
        }) else { return nil }
        let value = rawFieldValue(field.id)
        return value.isEmpty ? nil : value
    }

    /// Prix d'achat brut (montant + devise), tel que renseigné dans les champs personnalisés —
    /// `nil` si le champ n'est pas configuré ou laissé vide.
    private var purchasePrice: (amount: Double, currency: String)? {
        guard let fieldId = purchasePriceFieldId, let username = DiscogsAuthManager.shared.username else { return nil }
        let raw = rawFieldValue(fieldId).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return PurchasePriceParser.parse(raw, defaultCurrency: CollectionPreferencesStore.defaultCurrency(for: username))
    }

    /// Devise d'affichage de la plus-value : celle choisie dans Réglages → Suivi de cote (elle
    /// était auparavant toujours l'euro, quel que soit ce réglage).
    private var displayCurrency: String {
        guard let username = DiscogsAuthManager.shared.username else { return "EUR" }
        return CollectionPreferencesStore.defaultCurrency(for: username)
    }

    /// Plus/moins-value de l'exemplaire par rapport à son prix d'achat, exprimée dans la devise
    /// d'affichage (prix d'achat et cote marketplace sont chacun dans leur propre devise d'origine).
    @ViewBuilder
    private var gainSection: some View {
        if !PremiumStore.shared.isPremium {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(title: "Plus-value de l'exemplaire", icon: "arrow.left.arrow.right")
                // La cote seule est gratuite (donnée Discogs affichée avec son attribution) ; seule
                // sa comparaison au prix d'achat est réservée au Premium.
                if let marketEstimateInDisplayCurrency {
                    marketEstimateButton(price: marketEstimateInDisplayCurrency)
                        .appleMusicGroupedCard()
                }
                PremiumLockedCard(
                    icon: "arrow.left.arrow.right",
                    title: "Plus-value de l'exemplaire",
                    message: "Passe premium pour calculer la plus-value de cet album à partir de ton prix d'achat."
                )
            }
            .task(id: "\(item.releaseId)_\(declaredCondition ?? "")_\(displayCurrency)") {
                let estimate = await actions.refreshMarketEstimateIfNeeded(releaseId: item.releaseId, condition: declaredCondition)
                guard !Task.isCancelled else { return }
                if let estimate {
                    let converted = await CurrencyConversionService.shared.convert(estimate.price, from: estimate.currency, to: displayCurrency)
                    guard !Task.isCancelled else { return }
                    marketEstimateInDisplayCurrency = converted
                    marketEstimateStaleSince = estimate.staleSince
                } else {
                    marketEstimateInDisplayCurrency = nil
                    marketEstimateStaleSince = nil
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(title: "Plus-value de l'exemplaire", icon: "arrow.left.arrow.right", isPremiumFeature: true)

                if purchasePrice == nil {
                    Text("Renseigne ton prix d'achat dans les champs personnalisés ci-dessous pour suivre la plus-value de cet exemplaire.")
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .appleMusicGroupedCard()
                } else if isLoadingGain {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .appleMusicGroupedCard()
                } else if let purchasePriceInDisplayCurrency, let marketEstimateInDisplayCurrency {
                    VStack(spacing: 10) {
                        GainSummaryTiles(
                            summary: GainSummary(purchase: purchasePriceInDisplayCurrency, estimate: marketEstimateInDisplayCurrency),
                            currency: displayCurrency
                        )
                        // La cote reste une ligne à part : elle ouvre le Marketplace Discogs.
                        marketEstimateButton(price: marketEstimateInDisplayCurrency)
                            .appleMusicGroupedCard()
                    }
                } else {
                    Text(networkMonitor.isConnected ? "Cote actuelle indisponible pour le moment." : "Cote actuelle indisponible hors ligne.")
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .appleMusicGroupedCard()
                }
            }
            .task(id: "\(item.releaseId)_\(declaredCondition ?? "")_\(purchasePrice?.amount ?? 0)_\(purchasePrice?.currency ?? "")_\(displayCurrency)") {
                guard let purchasePrice else {
                    purchasePriceInDisplayCurrency = nil
                    marketEstimateInDisplayCurrency = nil
                    marketEstimateStaleSince = nil
                    return
                }
                isLoadingGain = true
                async let purchaseConversion = CurrencyConversionService.shared.convert(purchasePrice.amount, from: purchasePrice.currency, to: displayCurrency)
                async let estimate = actions.refreshMarketEstimateIfNeeded(releaseId: item.releaseId, condition: declaredCondition)
                purchasePriceInDisplayCurrency = await purchaseConversion
                if let marketEstimate = await estimate {
                    marketEstimateInDisplayCurrency = await CurrencyConversionService.shared.convert(marketEstimate.price, from: marketEstimate.currency, to: displayCurrency)
                    marketEstimateStaleSince = marketEstimate.staleSince
                } else {
                    marketEstimateInDisplayCurrency = nil
                    marketEstimateStaleSince = nil
                }
                isLoadingGain = false
            }
        }
    }

    /// Ligne de cote qui ouvre le Marketplace Discogs de la release (compte gratuit et Premium).
    private func marketEstimateButton(price: Double) -> some View {
        Button {
            showingMarketplaceSheet = true
        } label: {
            MarketEstimateRow(price: price, currency: displayCurrency, staleSince: marketEstimateStaleSince, showsChevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Ouvre le Marketplace Discogs pour cette release")
    }

    /// Rôle du champ dans le calcul de la plus-value, d'après les champs choisis dans Réglages.
    private func gainFieldRole(for field: CollectionField) -> SettingsFieldHighlight? {
        guard let username = DiscogsAuthManager.shared.username else { return nil }
        if field.id == CollectionPreferencesStore.purchasePriceFieldId(for: username) { return .purchasePrice }
        if field.id == CollectionPreferencesStore.mediaConditionFieldId(for: username) { return .mediaCondition }
        return nil
    }

    /// Renvoie vers le réglage du champ, mis en évidence à l'arrivée (même mécanisme que « Modifier »
    /// dans le guide de rangement).
    private func openGainFieldSetting(_ role: SettingsFieldHighlight) {
        dismiss()
        TabNavigationCoordinator.shared.openSettingsAtPurchaseField(role)
    }

    private var discRow: some View {
        ReleaseSheetHeader(
            coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb,
            title: item.basicInformation.title,
            artist: item.basicInformation.artistNames,
            pills: headerPills,
            onAverageColorLoaded: { coverTint = $0 }
        )
    }

    /// Année, format et dossier de l'exemplaire, en pastilles sous le titre.
    private var headerPills: [String] {
        var pills: [String] = []
        if let year = item.basicInformation.year, year > 0 { pills.append(String(year)) }
        if let format = item.basicInformation.formats?.first?.name, !format.isEmpty { pills.append(format) }
        if let folder = folders.first(where: { $0.id == selectedFolderId }), folder.id != DiscogsConstants.allFolderId {
            pills.append(folder.name)
        }
        return pills
    }

    private func binding(for field: CollectionField) -> Binding<String> {
        Binding(
            get: { fieldValues[field.id] ?? item.value(forFieldId: field.id) },
            set: { fieldValues[field.id] = $0 }
        )
    }

    private func saveField(_ field: CollectionField, value: String, afterDismiss: Bool = false) async {
        func report(_ message: String) {
            if afterDismiss {
                onSaveFailedAfterDismiss(message)
            } else {
                errorMessage = message
            }
        }
        // Démo : bloqué avant tout envoi ou mise en file (§7.2). Hors ligne, la modification partait
        // sinon dans la file et restait en attente pour un compte qui n'existe pas.
        if DemoMode.isActive {
            report(AppMessages.demoModificationBlocked)
            return
        }
        guard DiscogsAuthManager.shared.session != nil else {
            report(String(localized: "Tu dois être connecté à Discogs pour enregistrer ces modifications."))
            return
        }
        withAnimation {
            _ = savingFieldIds.insert(field.id)
        }
        let newValue = value
        let isOffline = !networkMonitor.isConnected

        func enqueueOffline() {
            OfflineSyncQueue.shared.enqueue(PendingAction(
                type: .updateCollectionField,
                releaseId: item.releaseId,
                folderId: item.folderId,
                instanceId: item.instanceId,
                fieldId: field.id,
                value: newValue
            ))
        }

        if isOffline {
            enqueueOffline()
        } else {
            do {
                try await actions.updateCollectionField(
                    folderId: item.folderId,
                    releaseId: item.releaseId,
                    instanceId: item.instanceId,
                    fieldId: field.id,
                    value: newValue
                )
            } catch where error.isTransientNetworkFailure {
                // Discogs injoignable malgré une connexion détectée (429, coupure...) : remis en
                // file plutôt que perdu silencieusement — même traitement que les autres
                // mutations dans `ReleaseActions`, qui distinguent déjà ce cas d'un refus définitif.
                enqueueOffline()
            } catch {
                withAnimation {
                    _ = savingFieldIds.remove(field.id)
                }
                report(String(localized: "Impossible d'enregistrer sur Discogs : \(error.localizedDescription)"))
                return
            }
        }

        savedFieldValues[field.id] = newValue

        var updatedNotes = item.notes
        updatedNotes.removeAll { $0.fieldId == field.id }
        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updatedNotes.append(CollectionFieldValue(fieldId: field.id, value: newValue))
        }
        onSaved(item.rating, updatedNotes)

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            _ = savingFieldIds.remove(field.id)
            _ = justSavedFieldIds.insert(field.id)
        }

        try? await Task.sleep(for: .seconds(2))
        withAnimation(.easeInOut(duration: 0.25)) {
            _ = justSavedFieldIds.remove(field.id)
        }
    }
}
