import SwiftUI

struct TagRenameItem: Identifiable, Equatable {
    var id: String { tag }
    let tag: String
}

/// Vue modale élégante et sans conflit pour renommer un tag ou le fusionner en cas de doublon
struct TagRenameSheet: View {
    let sourceTag: String
    @Environment(\.dismiss) private var dismiss
    @State private var store = TagStore.shared
    @State private var newName: String
    @State private var showingMergeConfirmation = false
    @State private var showingMaxLengthAlert = false
    @FocusState private var isFieldFocused: Bool

    init(tag: String) {
        self.sourceTag = tag
        self._newName = State(initialValue: tag)
    }

    private var trimmedNewName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSameName: Bool {
        trimmedNewName == sourceTag
    }

    private var targetTag: String? {
        guard !trimmedNewName.isEmpty, !isSameName else { return nil }
        return store.existingTag(matching: trimmedNewName)
    }

    private var isCollision: Bool {
        guard let target = targetTag else { return false }
        return target.caseInsensitiveCompare(sourceTag) != .orderedSame
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nom du tag")
                            .font(.subheadline)
                            .foregroundStyle(Color.appSecondaryText)

                        TextField("Nom du tag", text: $newName)
                            .font(.body)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .appleMusicGroupedCard()
                            .focused($isFieldFocused)
                            .submitLabel(isCollision ? .return : .done)
                            .onChange(of: newName) { _, newValue in
                                if newValue.count > TagConstants.maxNameLength {
                                    newName = String(newValue.prefix(TagConstants.maxNameLength))
                                    showingMaxLengthAlert = true
                                }
                            }
                            .onSubmit {
                                if !isCollision && !trimmedNewName.isEmpty && !isSameName {
                                    store.renameTag(sourceTag, to: trimmedNewName)
                                    dismiss()
                                }
                            }
                    }

                    if isCollision, let target = targetTag {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Tag déjà existant")
                                    .font(.subheadline.weight(.semibold))
                            }

                            Button {
                                showingMergeConfirmation = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.triangle.merge")
                                    Text("Fusionner avec « \(target) »")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .appleMusicGroupedCard()
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Renommer le tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if !isCollision && !trimmedNewName.isEmpty && !isSameName {
                            store.renameTag(sourceTag, to: trimmedNewName)
                            dismiss()
                        }
                    }
                    .disabled(trimmedNewName.isEmpty || isSameName || isCollision)
                    .fontWeight(.semibold)
                    .tint(Color.spinlogPink)
                }
            }
            .background(Color.appBackground)
            .confirmationDialog(
                "Confirmer la fusion des tags",
                isPresented: $showingMergeConfirmation,
                titleVisibility: .visible
            ) {
                if let target = targetTag {
                    Button("Fusionner les tags", role: .destructive) {
                        store.renameTag(sourceTag, to: target)
                        dismiss()
                    }
                    Button("Annuler", role: .cancel) {}
                }
            } message: {
                if let target = targetTag {
                    let sourceCount = store.instanceCount(for: sourceTag)
                    let targetCount = store.instanceCount(for: target)
                    Text("Tous les exemplaires associés à « \(sourceTag) » (\(sourceCount)) recevront le tag « \(target) » (\(targetCount)). Le tag « \(sourceTag) » sera définitivement supprimé.")
                }
            }
            .onAppear {
                isFieldFocused = true
            }
            .alert("Nom trop long", isPresented: $showingMaxLengthAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Le nom d'un tag est limité à \(TagConstants.maxNameLength) caractères.")
            }
        }
        .presentationDetents([.height(isCollision ? 300 : 210), .medium])
        .presentationDragIndicator(.visible)
    }
}

struct TagManagementView: View {
    /// Non-`nil` quand cette vue est ouverte pour appliquer un tag à une sélection en cours
    /// (édition en lot depuis Collection) plutôt que pour la gérer depuis Réglages : toucher un
    /// tag l'applique alors immédiatement et referme la sheet, au lieu d'ouvrir le renommage.
    var onApply: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var store = TagStore.shared
    @State private var searchText = ""
    @State private var renameItem: TagRenameItem?
    @State private var tagToDelete: String?
    @State private var duplicateTagError: String?
    @State private var showingMaxLengthAlert = false

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var exactMatchExists: Bool {
        store.allTags.contains { $0.caseInsensitiveCompare(trimmedQuery) == .orderedSame }
    }

    private var filteredTags: [String] {
        let all = store.allTags
        guard !trimmedQuery.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Bouton de création directe et fluide via la recherche
                if onApply != nil {
                    Text("Touche un tag pour l'ajouter à la sélection.")
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondaryText)
                }

                if !trimmedQuery.isEmpty && !exactMatchExists {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        store.createTag(trimmedQuery)
                        if let onApply {
                            onApply(trimmedQuery)
                            dismiss()
                        } else {
                            searchText = ""
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.spinlogPink)

                            Text("Créer le tag « \(trimmedQuery) »")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.spinlogPink)

                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .appleMusicGroupedCard()
                } else if !trimmedQuery.isEmpty && exactMatchExists {
                    // Indication sobre que le tag existe déjà
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)

                        Text("Tag déjà existant")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .appleMusicGroupedCard()
                }

                if store.allTags.isEmpty && trimmedQuery.isEmpty {
                    VStack(alignment: .center, spacing: 14) {
                        Image(systemName: "tag")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.spinlogPink.opacity(0.8))

                        Text("Aucun tag créé")
                            .font(.headline)

                        Text("Tape un nom dans la barre de recherche ci-dessus pour créer ton premier tag.")
                            .font(.subheadline)
                            .foregroundStyle(Color.appSecondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .padding(.horizontal, 20)
                } else if !filteredTags.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionEyebrow(title: "Tags créés (\(filteredTags.count))", icon: "tag.fill")

                        VStack(spacing: 0) {
                            ForEach(Array(filteredTags.enumerated()), id: \.element) { index, tag in
                                tagRow(tag)
                                if index < filteredTags.count - 1 {
                                    Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 14)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .appleMusicGroupedCard()

                        Text("Glisse vers la gauche pour modifier ou supprimer un tag.")
                            .font(.footnote)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }
            }
            .padding()
        }
        .swipeActionsContainer()
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Gestion des tags")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if onApply != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher ou créer un tag")
        .onChange(of: searchText) { _, newValue in
            if newValue.count > TagConstants.maxNameLength {
                searchText = String(newValue.prefix(TagConstants.maxNameLength))
                showingMaxLengthAlert = true
            }
        }
        .onSubmit(of: .search) {
            let trimmed = trimmedQuery
            guard !trimmed.isEmpty else { return }
            if exactMatchExists {
                duplicateTagError = trimmed
            } else {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                store.createTag(trimmed)
                searchText = ""
            }
        }
        .sheet(item: $renameItem) { item in
            TagRenameSheet(tag: item.tag)
        }
        .confirmationDialog(
            "Supprimer le tag",
            isPresented: Binding(
                get: { tagToDelete != nil },
                set: { if !$0 { tagToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let tag = tagToDelete {
                    store.deleteTag(tag)
                }
                tagToDelete = nil
            }
            Button("Annuler", role: .cancel) {
                tagToDelete = nil
            }
        } message: {
            if let tag = tagToDelete {
                let count = store.releaseCount(for: tag)
                Text("Veux-tu vraiment supprimer « \(tag) » ? Ce tag sera retiré de \(count) disques.")
            }
        }
        .alert("Tag déjà existant", isPresented: Binding(
            get: { duplicateTagError != nil },
            set: { if !$0 { duplicateTagError = nil } }
        )) {
            Button("OK", role: .cancel) {
                duplicateTagError = nil
            }
        } message: {
            if let name = duplicateTagError {
                Text("Le tag « \(name) » existe déjà dans ta bibliothèque.")
            }
        }
        .alert("Nom trop long", isPresented: $showingMaxLengthAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Le nom d'un tag est limité à \(TagConstants.maxNameLength) caractères.")
        }
    }

    private func tagRow(_ tag: String) -> some View {
        HStack(spacing: 12) {
            Text(tag)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.tagBackground, in: Capsule())
                .foregroundStyle(Color.tagForeground)

            Spacer()

            let count = store.instanceCount(for: tag)
            Text("\(count) ex.")
                .font(.footnote)
                .foregroundStyle(Color.appSecondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if let onApply {
                onApply(tag)
                dismiss()
            } else {
                renameItem = TagRenameItem(tag: tag)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                tagToDelete = tag
            } label: {
                Label("Supprimer", systemImage: "trash.fill")
            }
            .tint(.red)
            .labelStyle(.iconOnly)
            .accessibilityLabel("Supprimer ce tag")

            Button {
                renameItem = TagRenameItem(tag: tag)
            } label: {
                Label("Modifier", systemImage: "pencil")
            }
            .tint(.orange)
            .labelStyle(.iconOnly)
            .accessibilityLabel("Modifier ce tag")
        }
        .contextMenu {
            Button {
                renameItem = TagRenameItem(tag: tag)
            } label: {
                Label("Renommer", systemImage: "pencil")
            }

            Button(role: .destructive) {
                tagToDelete = tag
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }
}

#Preview {
    NavigationStack {
        TagManagementView()
    }
}
