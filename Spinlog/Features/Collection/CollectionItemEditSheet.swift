import SwiftUI

/// Édition des tags et des champs personnalisés Discogs (créés par l'utilisateur dans ses
/// réglages Discogs : état de la pochette, notes libres, etc.) pour un exemplaire de la collection.
/// La note (rating) n'est pas éditée ici : elle est globale à la release (partagée par Discogs
/// entre tous les exemplaires) et se gère depuis la carte "Ma note de la release" de la fiche release.
struct CollectionItemEditSheet: View {
    let item: CollectionItem
    @State private var fields: [CollectionField]
    /// Appelé après un enregistrement réussi, avec la note et les valeurs de champs à jour,
    /// pour que l'appelant (liste de collection ou fiche release) rafraîchisse son propre état.
    var onSaved: (Int, [CollectionFieldValue]) -> Void = { _, _ in }
    var onDelete: (() async -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var fieldValues: [Int: String]
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showingErrorAlert = false
    @State private var showingDeleteConfirmation = false

    init(
        item: CollectionItem,
        fields: [CollectionField],
        onSaved: @escaping (Int, [CollectionFieldValue]) -> Void = { _, _ in },
        onDelete: (() async -> Void)? = nil
    ) {
        self.item = item
        self._fields = State(initialValue: fields)
        self.onSaved = onSaved
        self.onDelete = onDelete
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
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    discRow

                    VStack(alignment: .leading, spacing: 10) {
                        SectionEyebrow(title: "Tags de l'exemplaire")
                        TagsEditor(instanceId: item.instanceId, releaseId: item.releaseId)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .appleMusicGroupedCard()
                        Text("Les tags sont des données locales à l'application et ne sont pas sauvegardés sur Discogs.")
                            .font(.footnote)
                            .foregroundStyle(Color.appSecondaryText)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionEyebrow(title: "Champs personnalisés Discogs")

                        if fields.isEmpty {
                            Text("Aucun champ personnalisé configuré")
                                .font(.subheadline)
                                .foregroundStyle(Color.appSecondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .appleMusicGroupedCard()
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                                    CollectionFieldControl(field: field, value: binding(for: field))
                                    if index < fields.count - 1 {
                                        Divider().opacity(0.15).padding(.leading, 14)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .appleMusicGroupedCard()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Contrairement aux tags qui sont des données locales à l'application et non sauvegardées sur Discogs, ces champs sont synchronisés avec votre compte. Discogs ne permet pas de créer ou supprimer des champs personnalisés en dehors de son site web : pour en créer, rendez-vous sur le site Discogs (Paramètres de collection) ; ils seront ensuite visibles dans l'application.")
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
                        .disabled(isSaving || isDeleting)
                    }
                }
                .padding()
            }
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Enregistrer") {
                            Task { await save() }
                        }
                        .fontWeight(.semibold)
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
                Text("Cet exemplaire sera définitivement retiré de votre collection Discogs.")
            }
            .task {
                if fields.isEmpty,
                   let username = DiscogsAuthManager.shared.username,
                   let credentials = DiscogsAuthManager.shared.credentials {
                    if let response = try? await DiscogsAPIClient.shared.collectionFields(username: username, credentials: credentials) {
                        fields = response.fields
                        for field in response.fields {
                            if fieldValues[field.id] == nil {
                                fieldValues[field.id] = item.value(forFieldId: field.id)
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

    private func save() async {
        guard let username = DiscogsAuthManager.shared.username,
              let credentials = DiscogsAuthManager.shared.credentials else {
            errorMessage = "Vous devez être connecté à Discogs pour enregistrer ces modifications."
            showingErrorAlert = true
            return
        }
        isSaving = true

        do {
            var updatedNotes = item.notes
            for field in fields {
                let newValue = fieldValues[field.id] ?? ""
                guard newValue != item.value(forFieldId: field.id) else { continue }
                try await DiscogsAPIClient.shared.updateCollectionField(
                    username: username,
                    folderId: item.folderId,
                    releaseId: item.releaseId,
                    instanceId: item.instanceId,
                    fieldId: field.id,
                    value: newValue,
                    credentials: credentials
                )
                updatedNotes.removeAll { $0.fieldId == field.id }
                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    updatedNotes.append(CollectionFieldValue(fieldId: field.id, value: newValue))
                }
            }

            isSaving = false
            onSaved(item.rating, updatedNotes)
            dismiss()
        } catch {
            isSaving = false
            errorMessage = "Impossible d'enregistrer sur Discogs : \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }
}

/// Ligne de champ personnalisé Discogs : libellé à gauche, contrôle adapté au type à droite
/// (texte, case à cocher, menu déroulant), ou en pleine largeur pour les zones de texte longues.
private struct CollectionFieldControl: View {
    let field: CollectionField
    @Binding var value: String

    var body: some View {
        if field.isTextArea {
            VStack(alignment: .leading, spacing: 6) {
                Text(field.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                TextField(field.name, text: $value, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(3...6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        } else if field.isCheckbox {
            Toggle(isOn: Binding(
                get: { value == "1" },
                set: { value = $0 ? "1" : "0" }
            )) {
                Text(field.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            .tint(Color.spinlogPink)
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}
