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

    @Environment(\.dismiss) private var dismiss
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var fieldValues: [Int: String]
    @State private var savedFieldValues: [Int: String]
    @State private var savingFieldIds: Set<Int> = []
    @State private var justSavedFieldIds: Set<Int> = []
    @State private var selectedFolderId: Int
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false
    @State private var safariRequest: SafariViewRequest?

    // MARK: - Plus-value de l'exemplaire
    /// Instance dédiée à la seule lecture de la cote marketplace (`refreshMarketEstimateIfNeeded`),
    /// sans rapport avec les dossiers/champs déjà gérés par cette feuille : pas de coût particulier
    /// à la créer ici, ses dépendances (compte, réseau, cache local) sont toutes des singletons.
    @State private var actions = ReleaseActions()
    @State private var purchasePriceEUR: Double?
    @State private var marketEstimateEUR: Double?
    @State private var isLoadingGain = false
    @State private var showingMarketplaceSheet = false

    init(
        item: CollectionItem,
        fields: [CollectionField],
        folders: [CollectionFolder] = [],
        onSaved: @escaping (Int, [CollectionFieldValue]) -> Void = { _, _ in },
        onFolderChanged: @escaping (CollectionItem, Int) -> Void = { _, _ in },
        onDelete: (() async -> Void)? = nil
    ) {
        self.item = item
        self.folders = folders
        self._fields = State(initialValue: fields)
        self.onSaved = onSaved
        self.onFolderChanged = onFolderChanged
        self.onDelete = onDelete
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
                                    ForEach(folders) { folder in
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
                            Text("Contrairement aux tags qui sont des données locales, ces champs sont synchronisés avec ton compte Discogs. La validation s'effectue automatiquement en cliquant en dehors du champ ou sur la coche.")
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
            .background(Color.appBackground)
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
                            await saveField(field, value: current)
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
                Text("Cet exemplaire sera définitivement retiré de ta collection Discogs.")
            }
            .sheet(isPresented: $showingMarketplaceSheet) {
                MarketplaceSheet(releaseId: item.releaseId)
            }
            .sheet(item: $safariRequest) { request in
                SafariView(url: request.url)
            }
            .task {
                if fields.isEmpty, let username = DiscogsAuthManager.shared.username {
                    let fetched = await ReleaseActions.fetchCollectionFields(username: username, credentials: DiscogsAuthManager.shared.credentials)
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

    /// Plus/moins-value de l'exemplaire par rapport à son prix d'achat, toujours exprimée en
    /// euros (prix d'achat et cote marketplace sont chacun dans leur propre devise d'origine).
    @ViewBuilder
    private var gainSection: some View {
        if !PremiumStore.shared.isPremium {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(title: "Plus-value de l'exemplaire", icon: "arrow.left.arrow.right")
                PremiumLockedCard(
                    icon: "arrow.left.arrow.right",
                    title: "Plus-value de l'exemplaire",
                    message: "Passe premium pour renseigner ton prix d'achat et suivre la plus-value de cet album."
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(title: "Plus-value de l'exemplaire", icon: "arrow.left.arrow.right")

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
                } else if let purchasePriceEUR, let marketEstimateEUR {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Prix d'achat")
                                .font(.subheadline)
                            Spacer()
                            Text(purchasePriceEUR.formatted(.currency(code: "EUR")))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 14)

                        Button {
                            showingMarketplaceSheet = true
                        } label: {
                            HStack {
                                Text("Cote actuelle")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(marketEstimateEUR.formatted(.currency(code: "EUR")))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.spinlogPink)
                                    .monospacedDigit()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.appTertiaryText)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Ouvre le Marketplace Discogs pour cette release")

                        Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 14)

                        let gain = marketEstimateEUR - purchasePriceEUR
                        let percent = purchasePriceEUR > 0 ? gain / purchasePriceEUR : 0
                        HStack {
                            Text("Plus-value latente")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(gain >= 0 ? "+" : "")\(gain.formatted(.currency(code: "EUR").precision(.fractionLength(0)))) (\(percent.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))))")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(gain >= 0 ? Color.gainPositive : Color.gainNegative)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .appleMusicGroupedCard()
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
            .task(id: "\(item.releaseId)_\(declaredCondition ?? "")_\(purchasePrice?.amount ?? 0)_\(purchasePrice?.currency ?? "")") {
                guard let purchasePrice else {
                    purchasePriceEUR = nil
                    marketEstimateEUR = nil
                    return
                }
                isLoadingGain = true
                async let purchaseConversion = CurrencyConversionService.shared.convert(purchasePrice.amount, from: purchasePrice.currency, to: "EUR")
                async let estimate = actions.refreshMarketEstimateIfNeeded(releaseId: item.releaseId, condition: declaredCondition)
                purchasePriceEUR = await purchaseConversion
                if let marketEstimate = await estimate {
                    marketEstimateEUR = await CurrencyConversionService.shared.convert(marketEstimate.price, from: marketEstimate.currency, to: "EUR")
                } else {
                    marketEstimateEUR = nil
                }
                isLoadingGain = false
            }
        }
    }

    private var discRow: some View {
        HStack(spacing: 12) {
            AsyncCoverImage(url: item.basicInformation.thumb ?? item.basicInformation.coverImage, cornerRadius: 8)
                .frame(width: 54, height: 54)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 3)
                .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.basicInformation.title)
                    .font(.body.bold())
                Text(item.basicInformation.artistNames)
                    .font(.subheadline)
                    .foregroundStyle(Color.appSecondaryText)
            }
            Spacer(minLength: 0)
        }
    }

    private func binding(for field: CollectionField) -> Binding<String> {
        Binding(
            get: { fieldValues[field.id] ?? item.value(forFieldId: field.id) },
            set: { fieldValues[field.id] = $0 }
        )
    }

    private func saveField(_ field: CollectionField, value: String) async {
        guard DiscogsAuthManager.shared.session != nil else {
            errorMessage = String(localized: "Tu dois être connecté à Discogs pour enregistrer ces modifications.")
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
                errorMessage = String(localized: "Impossible d'enregistrer sur Discogs : \(error.localizedDescription)")
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

/// Ligne de champ personnalisé Discogs : libellé à gauche, contrôle adapté au type à droite
/// (texte, case à cocher, menu déroulant), ou en pleine largeur pour les zones de texte longues.
/// Dispose d'un bouton coche dédié pour forcer la validation et l'envoi immédiat à Discogs,
/// et valide automatiquement dès que l'utilisateur clique en dehors du champ (perte de focus).
/// Même carte par ligne que le reste de la feuille (dossier, tags…) : pas de fond supplémentaire
/// propre à chaque contrôle, qui ferait double emploi avec `.appleMusicGroupedCard()` et
/// alourdirait la liste. Un menu déroulant ou une case à cocher se signalent déjà d'eux-mêmes
/// (chevron système, interrupteur) ; un simple champ texte, sans ce genre d'indice visuel natif,
/// reçoit un petit crayon discret tant qu'il est vide et qu'on n'y touche pas — une fois rempli,
/// sa valeur s'affiche dans le rose de l'app, cet indice-là suffit.
private struct CollectionFieldControl: View {
    let field: CollectionField
    @Binding var value: String
    let isDirty: Bool
    let isSaving: Bool
    let justSaved: Bool
    let onSave: () -> Void

    @FocusState private var isFocused: Bool

    private var hasValue: Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsEditHint: Bool {
        !isFocused && !isDirty && !isSaving && !justSaved && !hasValue
    }

    var body: some View {
        Group {
            if field.isTextArea {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(field.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        editHintIcon
                        trailingStatusView
                    }
                    TextField(field.name, text: $value, axis: .vertical)
                        .font(.subheadline)
                        .foregroundStyle(hasValue ? Color.spinlogPink : .primary)
                        .lineLimit(3...6)
                        .focused($isFocused)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else if field.isCheckbox {
                HStack {
                    Toggle(isOn: Binding(
                        get: { value == "1" },
                        set: { value = $0 ? "1" : "0" }
                    )) {
                        Text(field.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .tint(Color.spinlogPink)

                    trailingStatusView
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else if field.isDropdown {
                HStack {
                    Text(field.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Picker("", selection: $value) {
                        Text("—").tag("")
                        ForEach(field.options ?? [], id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(Color.spinlogPink)

                    trailingStatusView
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else {
                HStack {
                    Text(field.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    editHintIcon
                    TextField(field.name, text: $value)
                        .font(.subheadline)
                        .foregroundStyle(hasValue ? Color.spinlogPink : .primary)
                        .multilineTextAlignment(.trailing)
                        .focused($isFocused)
                        .onSubmit {
                            isFocused = false
                            if isDirty && !isSaving {
                                onSave()
                            }
                        }

                    trailingStatusView
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .onChange(of: isFocused) { wasFocused, nowFocused in
            if wasFocused && !nowFocused {
                if isDirty && !isSaving {
                    onSave()
                }
            }
        }
        .onChange(of: value) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if (field.isDropdown || field.isCheckbox) && isDirty && !isSaving {
                onSave()
            }
        }
    }

    /// Crayon discret, même symbole que l'action de swipe "Modifier" ailleurs dans l'app : le
    /// seul indice dont un simple champ texte a besoin pour se signaler comme modifiable, sans
    /// repasser dessus un fond ou une bordure qui romprait avec le reste de la feuille.
    @ViewBuilder
    private var editHintIcon: some View {
        if showsEditHint {
            Image(systemName: "pencil")
                .font(.caption2)
                .foregroundStyle(Color.appTertiaryText)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var trailingStatusView: some View {
        if isSaving {
            ProgressView()
                .controlSize(.small)
                .padding(.leading, 6)
        } else if justSaved {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .padding(.leading, 6)
                .transition(.scale.combined(with: .opacity))
        } else if isDirty {
            Button {
                isFocused = false
                onSave()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.spinlogPink)
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Valider et enregistrer ce champ sur Discogs")
        }
    }
}
