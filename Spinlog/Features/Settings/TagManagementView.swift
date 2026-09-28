import SwiftUI

struct TagManagementView: View {
    @State private var store = TagStore.shared
    @State private var searchText = ""
    @State private var showingCreateAlert = false
    @State private var newTagInput = ""
    @State private var tagToRename: String?
    @State private var renameInput = ""
    @State private var tagToDelete: String?
    @State private var showingDeleteAllConfirmation = false

    private var filteredTags: [String] {
        let all = store.allTags
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group {
            if store.allTags.isEmpty {
                ContentUnavailableView {
                    Label("Aucun tag", systemImage: "tag.slash")
                } description: {
                    Text("Créez des tags ici ou attribuez-en à vos disques depuis la fiche détaillée d'un vinyle.")
                } actions: {
                    Button("Créer un tag") {
                        newTagInput = ""
                        showingCreateAlert = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if filteredTags.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    Section {
                        ForEach(filteredTags, id: \.self) { tag in
                            HStack(spacing: 12) {
                                Text(tag)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.tagBackground, in: Capsule())
                                    .foregroundStyle(Color.tagForeground)

                                Spacer()

                                let count = store.releaseCount(for: tag)
                                Text(count <= 1 ? "\(count) disque" : "\(count) disques")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                tagToRename = tag
                                renameInput = tag
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    tagToDelete = tag
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }

                                Button {
                                    tagToRename = tag
                                    renameInput = tag
                                } label: {
                                    Label("Renommer", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                            .contextMenu {
                                Button {
                                    tagToRename = tag
                                    renameInput = tag
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
                    } header: {
                        Text("\(filteredTags.count) \(filteredTags.count <= 1 ? "tag" : "tags")")
                    } footer: {
                        Text("Touchez un tag ou glissez vers la gauche pour le renommer ou le supprimer. La modification sera répercutée sur tous les disques associés.")
                    }
                }
            }
        }
        .navigationTitle("Gestion des tags")
        .searchable(text: $searchText, prompt: "Rechercher un tag")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    Button {
                        newTagInput = ""
                        showingCreateAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Nouveau tag")

                    if !store.allTags.isEmpty {
                        Menu {
                            Button(role: .destructive) {
                                showingDeleteAllConfirmation = true
                            } label: {
                                Label("Supprimer tous les tags", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Options des tags")
                    }
                }
            }
        }
        .alert("Nouveau tag", isPresented: $showingCreateAlert) {
            TextField("Nom du tag", text: $newTagInput)
            Button("Créer") {
                store.createTag(newTagInput)
                newTagInput = ""
            }
            .disabled(newTagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Annuler", role: .cancel) {
                newTagInput = ""
            }
        } message: {
            Text("Ce tag sera disponible dans les suggestions pour tous vos disques.")
        }
        .alert("Renommer le tag", isPresented: Binding(
            get: { tagToRename != nil },
            set: { if !$0 { tagToRename = nil } }
        )) {
            TextField("Nouveau nom", text: $renameInput)
            Button("Enregistrer") {
                if let oldTag = tagToRename {
                    store.renameTag(oldTag, to: renameInput)
                }
                tagToRename = nil
            }
            .disabled(renameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Annuler", role: .cancel) {
                tagToRename = nil
            }
        } message: {
            if let oldTag = tagToRename {
                let count = store.releaseCount(for: oldTag)
                Text("Le renommage s'appliquera à \(count <= 1 ? "1 disque associé" : "\(count) disques associés").")
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
                Text("Êtes-vous sûr de vouloir supprimer « \(tag) » ? Ce tag sera retiré de \(count <= 1 ? "1 disque" : "\(count) disques").")
            }
        }
        .confirmationDialog(
            "Supprimer tous les tags ?",
            isPresented: $showingDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer tous les tags", role: .destructive) {
                store.removeAllTags()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tous les tags seront définitivement supprimés et retirés de vos disques. Cette action est irréversible.")
        }
    }
}

#Preview {
    NavigationStack {
        TagManagementView()
    }
}
