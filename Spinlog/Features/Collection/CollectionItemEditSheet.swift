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
    @State private var showingErrorAlert = false
    @State private var showingDeleteConfirmation = false

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

                    if !PremiumStore.shared.isPremium {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionEyebrow(title: "Plus-value de l'exemplaire", icon: "arrow.left.arrow.right")
                            PremiumLockedCard(
                                icon: "arrow.left.arrow.right",
                                title: "Plus-value de l'exemplaire",
                                message: "Passe premium pour renseigner ton prix d'achat et suivre la plus-value de cet album."
                            )
                        }
                    }

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
                                        Divider().opacity(0.15).padding(.leading, 14)
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

                            Link(destination: URL(string: "https://www.discogs.com/settings/collection")!) {
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
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            .alert("Erreur", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Une erreur est survenue lors de l'enregistrement sur Discogs.")
            }
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

    private var discRow: some View {
        HStack(spacing: 12) {
            AsyncCoverImage(url: item.basicInformation.thumb ?? item.basicInformation.coverImage, cornerRadius: 8)
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.basicInformation.title)
                    .font(.subheadline.bold())
                Text(item.basicInformation.artistNames)
                    .font(.caption)
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
        guard let (username, credentials) = DiscogsAuthManager.shared.session else {
            errorMessage = String(localized: "Tu dois être connecté à Discogs pour enregistrer ces modifications.")
            showingErrorAlert = true
            return
        }
        withAnimation {
            _ = savingFieldIds.insert(field.id)
        }
        let isOffline = !networkMonitor.isConnected

        do {
            let newValue = value
            if isOffline {
                OfflineSyncQueue.shared.enqueue(PendingAction(
                    type: .updateCollectionField,
                    releaseId: item.releaseId,
                    folderId: item.folderId,
                    instanceId: item.instanceId,
                    fieldId: field.id,
                    value: newValue
                ))
            } else {
                try await DiscogsAPIClient.shared.updateCollectionField(
                    username: username,
                    folderId: item.folderId,
                    releaseId: item.releaseId,
                    instanceId: item.instanceId,
                    fieldId: field.id,
                    value: newValue,
                    credentials: credentials
                )
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
        } catch {
            withAnimation {
                _ = savingFieldIds.remove(field.id)
            }
            errorMessage = String(localized: "Impossible d'enregistrer sur Discogs : \(error.localizedDescription)")
            showingErrorAlert = true
        }
    }
}

/// Ligne de champ personnalisé Discogs : libellé à gauche, contrôle adapté au type à droite
/// (texte, case à cocher, menu déroulant), ou en pleine largeur pour les zones de texte longues.
/// Dispose d'un bouton coche dédié pour forcer la validation et l'envoi immédiat à Discogs,
/// et valide automatiquement dès que l'utilisateur clique en dehors du champ (perte de focus).
private struct CollectionFieldControl: View {
    let field: CollectionField
    @Binding var value: String
    let isDirty: Bool
    let isSaving: Bool
    let justSaved: Bool
    let onSave: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if field.isTextArea {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(field.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        trailingStatusView
                    }
                    TextField(field.name, text: $value, axis: .vertical)
                        .font(.subheadline)
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
                    .tint(Color.appSecondaryText)

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
                    TextField(field.name, text: $value)
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondaryText)
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
