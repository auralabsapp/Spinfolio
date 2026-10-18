import SwiftUI

enum BulkTagStatus: Equatable {
    case all
    case partial(count: Int)
    case none
}

struct BulkPartialTagAction: Identifiable {
    var id: String { tag }
    let tag: String
    let count: Int
}

/// Feuille de gestion des tags pour une sélection multiple d'exemplaires.
/// Permet d'ajouter ou retirer plusieurs tags d'affilée, d'en créer de nouveaux,
/// et de visualiser l'état de chaque tag sur l'ensemble de la sélection.
struct BulkTagManagementSheet: View {
    let items: [CollectionItem]
    var onCompletion: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var store = TagStore.shared
    @State private var searchText = ""
    @State private var renameItem: TagRenameItem? = nil
    @State private var tagToDelete: String? = nil
    @State private var partialTagAction: BulkPartialTagAction? = nil
    @State private var duplicateTagError: String? = nil
    @State private var showingMaxLengthAlert = false
    @State private var showingMaxTagsAlert = false
    @State private var hasModified = false

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

    private func tagStatus(for tag: String) -> BulkTagStatus {
        guard !items.isEmpty else { return .none }
        let count = items.filter { item in
            let tags = store.tags(for: item.instanceId, releaseId: item.releaseId)
            return tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }.count

        if count == items.count {
            return .all
        } else if count > 0 {
            return .partial(count: count)
        } else {
            return .none
        }
    }

    private func addTagToAll(_ tag: String) {
        let trimmed = String(tag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(TagConstants.maxNameLength))
        guard !trimmed.isEmpty else { return }

        var hadLimitIssue = false
        // Une seule écriture et un seul recalcul de la collection pour tout le lot.
        store.performBatchUpdate {
            for item in items {
                let current = store.tags(for: item.instanceId, releaseId: item.releaseId)
                let alreadyHas = current.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
                if !alreadyHas {
                    if current.count >= TagConstants.maxTagsPerInstance {
                        hadLimitIssue = true
                    } else {
                        store.addTag(trimmed, to: item.instanceId, releaseId: item.releaseId)
                    }
                }
            }
        }

        if hadLimitIssue {
            showingMaxTagsAlert = true
        }
        hasModified = true
    }

    private func removeTagFromAll(_ tag: String) {
        store.performBatchUpdate {
            for item in items {
                store.removeTag(tag, from: item.instanceId, releaseId: item.releaseId)
            }
        }
        hasModified = true
    }

    private func handleTagTap(_ tag: String) {
        let status = tagStatus(for: tag)
        switch status {
        case .all:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            removeTagFromAll(tag)
        case .none:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            addTagToAll(tag)
        case .partial(let count):
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            partialTagAction = BulkPartialTagAction(tag: tag, count: count)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // En-tête explicatif
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(items.count) exemplaires sélectionnés")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.spinlogPink)

                        Text("Touche un tag pour l'ajouter ou le retirer des exemplaires sélectionnés.")
                            .font(.footnote)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                    .padding(.horizontal, 4)

                    // Création directe via la barre de recherche
                    if !trimmedQuery.isEmpty && !exactMatchExists {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            store.createTag(trimmedQuery)
                            addTagToAll(trimmedQuery)
                            searchText = ""
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.spinlogPink)

                                Text("Créer et ajouter « \(trimmedQuery) » à la sélection")
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
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.spinlogPink)

                            Text("Le tag « \(trimmedQuery) » existe déjà. Touche-le ci-dessous pour l'appliquer.")
                                .font(.footnote)
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

                            Text("Tape un nom dans la barre de recherche pour créer et appliquer ton premier tag.")
                                .font(.subheadline)
                                .foregroundStyle(Color.appSecondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                        .padding(.horizontal, 20)
                    } else if !filteredTags.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionEyebrow(title: "Tags disponibles (\(filteredTags.count))", icon: "tag.fill")

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

                            Text("Légende : coche rose = présent sur tous, tiret orange = présent sur certains, cercle vide = absent.")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
                .padding()
            }
            .swipeActionsContainerIfAvailable()
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Tags de la sélection")
            .navigationBarTitleDisplayMode(.inline)
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
                    if let existing = store.existingTag(matching: trimmed) {
                        handleTagTap(existing)
                    }
                    searchText = ""
                } else {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    store.createTag(trimmed)
                    addTagToAll(trimmed)
                    searchText = ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .tint(Color.spinlogPink)
                }
            }
            .onDisappear {
                if hasModified {
                    onCompletion?()
                }
            }
            .sheet(item: $renameItem) { item in
                TagRenameSheet(tag: item.tag)
            }
            .confirmationDialog(
                "Tag « \(partialTagAction?.tag ?? "") »",
                isPresented: Binding(
                    get: { partialTagAction != nil },
                    set: { if !$0 { partialTagAction = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let action = partialTagAction {
                    Button("Ajouter à tous les exemplaires (\(items.count))") {
                        addTagToAll(action.tag)
                        partialTagAction = nil
                    }
                    Button("Retirer de toute la sélection", role: .destructive) {
                        removeTagFromAll(action.tag)
                        partialTagAction = nil
                    }
                    Button("Annuler", role: .cancel) {
                        partialTagAction = nil
                    }
                }
            } message: {
                if let action = partialTagAction {
                    Text("Ce tag est actuellement attribué à \(action.count) exemplaires sur \(items.count). Que veux-tu faire ?")
                }
            }
            .confirmationDialog(
                "Supprimer le tag",
                isPresented: Binding(
                    get: { tagToDelete != nil },
                    set: { if !$0 { tagToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Supprimer de la bibliothèque", role: .destructive) {
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
                    Text("Veux-tu vraiment supprimer définitivement « \(tag) » ? Ce tag sera retiré de \(count) disques de ta bibliothèque.")
                }
            }
            .alert("Nom trop long", isPresented: $showingMaxLengthAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Le nom d'un tag est limité à \(TagConstants.maxNameLength) caractères.")
            }
            .alert("Limite de tags atteinte", isPresented: $showingMaxTagsAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Certains exemplaires ont déjà atteint la limite maximale de \(TagConstants.maxTagsPerInstance) tags et n'ont pas pu recevoir ce tag.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func tagRow(_ tag: String) -> some View {
        let status = tagStatus(for: tag)
        return HStack(spacing: 12) {
            Text(tag)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.tagBackground, in: Capsule())
                .foregroundStyle(Color.tagForeground)

            Spacer()

            switch status {
            case .all:
                Text("Tous (\(items.count))")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.spinlogPink)

                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.spinlogPink)

            case .partial(let count):
                Text("\(count)/\(items.count)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)

                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)

            case .none:
                let totalCount = store.instanceCount(for: tag)
                if totalCount > 0 {
                    Text("\(totalCount) ex.")
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondaryText)
                }

                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(Color.secondary.opacity(0.35))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTagTap(tag)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            if status != .all {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    addTagToAll(tag)
                } label: {
                    Label("Ajouter à toute la sélection", systemImage: "plus.circle")
                }
            }

            if status != .none {
                Button(role: .destructive) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    removeTagFromAll(tag)
                } label: {
                    Label("Retirer de toute la sélection", systemImage: "minus.circle")
                }
            }

            Divider().overlay(Color.appSeparator)

            Button {
                renameItem = TagRenameItem(tag: tag)
            } label: {
                Label("Renommer le tag", systemImage: "pencil")
            }

            Button(role: .destructive) {
                tagToDelete = tag
            } label: {
                Label("Supprimer de la bibliothèque", systemImage: "trash")
            }
        }
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
    }
}
