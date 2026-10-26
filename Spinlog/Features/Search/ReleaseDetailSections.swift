import SwiftUI

/// Barre d'actions rapides tactiles (Collection, Wantlist) style Apple Music
struct ReleaseQuickActionsBar: View {
    let releaseId: Int
    var release: Release? = nil
    var actions: ReleaseActions
    var onShowShelfPlacement: (() -> Void)? = nil

    @State private var authManager = DiscogsAuthManager.shared
    @State private var instancePendingDeletion: CollectionItem? = nil
    @State private var showDeleteAllConfirmation = false
    @State private var showSingleDeleteConfirmation = false
    @State private var showWantlistDeleteConfirmation = false
    /// Compteurs qui déclenchent le « pop » des boutons après un ajout (voir `libraryPop`).
    @State private var collectionPop = 0
    @State private var wantlistPop = 0

    private var isAlwaysAsk: Bool {
        guard let username = authManager.username else { return false }
        return CollectionPreferencesStore.isAlwaysAsk(for: username)
    }

    /// Dossiers où ranger un exemplaire : « All » est une vue agrégée de Discogs, pas un dossier.
    private var effectiveFolders: [CollectionFolder] {
        let targetFolders = actions.folders.filter { $0.id != DiscogsConstants.allFolderId }
        if !targetFolders.isEmpty {
            return targetFolders
        }
        return [CollectionFolder(id: DiscogsConstants.uncategorizedFolderId, name: "Uncategorized", count: 0)]
    }

    private var collectionButtonTitle: String {
        if actions.isInCollection {
            if actions.instancesCount > 1 {
                return String(localized: "En collection (\(actions.instancesCount))")
            }
            return String(localized: "En collection")
        }
        return String(localized: "Collection")
    }

    private var collectionButtonLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: actions.isInCollection ? "checkmark" : "plus")
                .font(.subheadline.bold())
                .contentTransition(.symbolEffect(.replace))
            Text(collectionButtonTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(actions.isInCollection ? Color.onAccentGradient : Color.primary)
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(
            Group {
                if actions.isInCollection {
                    Capsule()
                        .fill(Color.spinlogPinkButtonGradient)
                        .shadow(color: Color.buttonPinkShadow, radius: 4, y: 1.5)
                } else {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                }
            }
        )
        .contentShape(Capsule())
        .libraryPop(trigger: collectionPop)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Bouton Collection (bascule ajout/retrait instantanée ou menu selon réglages/exemplaires)
            if actions.isInCollection && actions.instancesCount > 1 {
                // Plusieurs exemplaires : menu au tap direct pour ajouter une copie ou retirer
                Menu {
                    Section {
                        if isAlwaysAsk {
                            Menu("Ajouter un autre exemplaire") {
                                ForEach(effectiveFolders) { folder in
                                    Button(folder.name) {
                                        Task {
                                            await actions.addToCollection(
                                                releaseId: releaseId,
                                                release: release,
                                                targetFolderId: folder.id
                                            )
                                        }
                                    }
                                }
                            }
                        } else {
                            Button("Ajouter un autre exemplaire") {
                                Task {
                                    await actions.addToCollection(
                                        releaseId: releaseId,
                                        release: release
                                    )
                                }
                            }
                        }
                    }

                    Section("Gérer les exemplaires") {
                        ForEach(Array(actions.collectionInstances.enumerated()), id: \.element.id) { index, inst in
                            Button(role: .destructive) {
                                instancePendingDeletion = inst
                            } label: {
                                Label("Supprimer exemplaire \(index + 1) (\(actions.folderName(for: inst.folderId)))", systemImage: "trash")
                            }
                        }

                        Button("Supprimer tous les exemplaires", role: .destructive) {
                            showDeleteAllConfirmation = true
                        }
                    }

                    Section {
                        Button {
                            onShowShelfPlacement?()
                        } label: {
                            Label("Emplacement dans mon meuble", systemImage: "books.vertical.fill")
                        }
                    }
                } label: {
                    collectionButtonLabel
                }
                .buttonStyle(.plain)
            } else if actions.isInCollection {
                Button {
                    showSingleDeleteConfirmation = true
                } label: {
                    collectionButtonLabel
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if isAlwaysAsk {
                        Menu("Ajouter un autre exemplaire") {
                            ForEach(effectiveFolders) { folder in
                                Button(folder.name) {
                                    Task {
                                        await actions.addToCollection(
                                            releaseId: releaseId,
                                            release: release,
                                            targetFolderId: folder.id
                                        )
                                    }
                                }
                            }
                        }
                    } else {
                        Button("Ajouter un autre exemplaire") {
                            Task {
                                await actions.addToCollection(
                                    releaseId: releaseId,
                                    release: release
                                )
                            }
                        }
                    }

                    Button(role: .destructive) {
                        showSingleDeleteConfirmation = true
                    } label: {
                        Label("Supprimer de la collection", systemImage: "trash")
                    }

                    Section {
                        Button {
                            onShowShelfPlacement?()
                        } label: {
                            Label("Emplacement dans mon meuble", systemImage: "books.vertical.fill")
                        }
                    }
                }
            } else if isAlwaysAsk {
                Menu {
                    ForEach(effectiveFolders) { folder in
                        Button(folder.name) {
                            Task {
                                await actions.addToCollection(
                                    releaseId: releaseId,
                                    release: release,
                                    targetFolderId: folder.id
                                )
                            }
                        }
                    }
                } label: {
                    collectionButtonLabel
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task {
                        await actions.addToCollection(
                            releaseId: releaseId,
                            release: release
                        )
                    }
                } label: {
                    collectionButtonLabel
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if effectiveFolders.count > 1 {
                        ForEach(effectiveFolders) { folder in
                            Button(folder.name) {
                                Task {
                                    await actions.addToCollection(
                                        releaseId: releaseId,
                                        release: release,
                                        targetFolderId: folder.id
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // Bouton Wantlist (bascule ajout/retrait avec confirmation)
            Button {
                if actions.isInWantlist {
                    showWantlistDeleteConfirmation = true
                } else {
                    Task { await actions.toggleWantlist(releaseId: releaseId, release: release) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: actions.isInWantlist ? "checkmark" : "heart.fill")
                        .font(.subheadline.bold())
                        .contentTransition(.symbolEffect(.replace))
                    Text(actions.isInWantlist ? "En wantlist" : "Wantlist")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(actions.isInWantlist ? Color.onAccentGradient : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    Group {
                        if actions.isInWantlist {
                            Capsule()
                                .fill(Color.spinlogPinkButtonGradient)
                                .shadow(color: Color.buttonPinkShadow, radius: 4, y: 1.5)
                        } else {
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        }
                    }
                )
                .contentShape(Capsule())
                .libraryPop(trigger: wantlistPop)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("releaseWantlistButton")
        }
        .animation(.easeInOut(duration: 0.15), value: actions.isInCollection)
        .animation(.easeInOut(duration: 0.15), value: actions.isInWantlist)
        .onChange(of: actions.lastFeedbackEvent) { _, event in
            guard let event, event.kind.isAddition else { return }
            if event.kind == .addedToCollection {
                collectionPop += 1
            } else {
                wantlistPop += 1
            }
        }
        .task {
            await actions.loadFoldersIfNeeded()
        }
        .confirmationDialog(
            "Supprimer cet exemplaire ?",
            isPresented: Binding(
                get: { instancePendingDeletion != nil },
                set: { if !$0 { instancePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let inst = instancePendingDeletion {
                    Task { await actions.removeInstance(inst) }
                }
                instancePendingDeletion = nil
            }
            Button("Annuler", role: .cancel) {
                instancePendingDeletion = nil
            }
        } message: {
            if let inst = instancePendingDeletion {
                Text("Supprimer cet exemplaire (dossier « \(actions.folderName(for: inst.folderId)) ») de ta collection Discogs ?")
            }
        }
        .confirmationDialog(
            "Supprimer tous les exemplaires ?",
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer tous les exemplaires", role: .destructive) {
                Task { await actions.removeFromCollection(releaseId: releaseId) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tous tes exemplaires de cet album seront supprimés de ta collection Discogs.")
        }
        .confirmationDialog(
            "Supprimer de la collection ?",
            isPresented: $showSingleDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer de la collection", role: .destructive) {
                Task { await actions.removeFromCollection(releaseId: releaseId) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Veux-tu supprimer cet album de ta collection Discogs ?")
        }
        .confirmationDialog(
            "Supprimer de la wantlist ?",
            isPresented: $showWantlistDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer de la wantlist", role: .destructive) {
                Task { await actions.toggleWantlist(releaseId: releaseId, release: release) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Veux-tu supprimer cet album de ta wantlist Discogs ?")
        }
        .messageAlert(
            DemoMode.isActive ? Text("Mode démo") : Text(verbatim: "Discogs"),
            message: Bindable(actions).message
        )
    }
}

