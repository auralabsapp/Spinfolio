import SwiftUI

/// Confirmations de la Collection (suppression d'un exemplaire, suppression et déplacement en
/// lot) et feuille des tags de la sélection. Extrait de `CollectionView`, dont l'état est passé
/// en liaisons.
struct CollectionDeletionAndBulkDialogs: ViewModifier {
    let viewModel: CollectionViewModel
    @Binding var itemPendingDeletion: CollectionItem?
    @Binding var showingBulkDeleteConfirmation: Bool
    @Binding var pendingMoveFolder: CollectionFolder?
    @Binding var showingBulkTagManagement: Bool
    @Binding var isSelecting: Bool
    @Binding var selectedItemIds: Set<Int>
    @Binding var isBulkProcessing: Bool
    /// Exemplaires sélectionnés, dans leur ordre d'apparition.
    let selectedItems: [CollectionItem]

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Supprimer de la collection ?",
                isPresented: Binding(
                    get: { itemPendingDeletion != nil },
                    set: { if !$0 { itemPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Supprimer de la collection", role: .destructive) {
                    if let item = itemPendingDeletion {
                        Task { await viewModel.remove(item) }
                    }
                    itemPendingDeletion = nil
                }
                Button("Annuler", role: .cancel) {
                    itemPendingDeletion = nil
                }
            } message: {
                if let item = itemPendingDeletion {
                    Text("Veux-tu supprimer « \(item.basicInformation.title) » de ta collection Discogs ?")
                }
            }
            .confirmationDialog(
                "Supprimer \(selectedItemIds.count) exemplaires de la collection ?",
                isPresented: $showingBulkDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    let targets = selectedItems
                    // Sortie immédiate du mode sélection : les exemplaires disparaissent de la liste
                    // d'un coup et Discogs est mis à jour en arrière-plan (voir `removeInstances`).
                    endSelection()
                    Task { await viewModel.removeInstances(targets) }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Cette action supprime définitivement ces exemplaires de ta collection Discogs.")
            }
            .confirmationDialog(
                moveConfirmationTitle,
                isPresented: Binding(
                    get: { pendingMoveFolder != nil },
                    set: { if !$0 { pendingMoveFolder = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let folder = pendingMoveFolder {
                    Button("Déplacer") {
                        let targets = selectedItems
                        Task {
                            isBulkProcessing = true
                            await viewModel.moveInstances(targets, toFolderId: folder.id)
                            isBulkProcessing = false
                            endSelection()
                        }
                        pendingMoveFolder = nil
                    }
                }
                Button("Annuler", role: .cancel) {
                    pendingMoveFolder = nil
                }
            }
            .sheet(isPresented: $showingBulkTagManagement) {
                BulkTagManagementSheet(items: selectedItems, onCompletion: endSelection)
            }
    }

    private func endSelection() {
        withAnimation {
            isSelecting = false
            selectedItemIds.removeAll()
        }
    }

    /// Titre de la confirmation de déplacement en lot. Deux littéraux complets plutôt qu'un
    /// ternaire imbriqué dans une seule interpolation : c'est ce qui permet au catalogue de
    /// chaînes de les extraire et les traduire correctement (un ternaire imbriqué produirait un
    /// texte français figé, non traduisible, à l'intérieur d'une chaîne par ailleurs localisée).
    private var moveConfirmationTitle: LocalizedStringKey {
        guard let folder = pendingMoveFolder else { return "" }
        if selectedItemIds.count > 1 {
            return "Déplacer les \(selectedItemIds.count) exemplaires dans le dossier \(folder.name) ?"
        } else {
            return "Déplacer l'exemplaire dans le dossier \(folder.name) ?"
        }
    }
}

/// Barre d'actions en lot façon app Fichiers : pile flottante en vrai Liquid Glass
/// (`glassEffect`) qui remplace la barre d'onglets pendant la sélection (masquée via
/// `.toolbar(.hidden, for: .tabBar)`), icônes grisées tant qu'aucun exemplaire n'est
/// sélectionné plutôt que la barre entière qui disparaîtrait.
struct CollectionBulkActionsBar: View {
    let folders: [CollectionFolder]
    let isSelecting: Bool
    let isEmpty: Bool
    let isProcessing: Bool
    let onMove: (CollectionFolder) -> Void
    let onManageTags: () -> Void
    let onDelete: () -> Void

    var body: some View {
        LibraryBulkActionsBar(isSelecting: isSelecting, isEmpty: isEmpty, isProcessing: isProcessing) {
            HStack(spacing: 36) {
                Menu {
                    ForEach(folders.filter { $0.id != DiscogsConstants.allFolderId }) { folder in
                        Button(folder.name) {
                            onMove(folder)
                        }
                    }
                } label: {
                    Image(systemName: "folder")
                        .font(.title3)
                }
                .accessibilityLabel("Déplacer la sélection dans un dossier")

                Button(action: onManageTags) {
                    Image(systemName: "tag")
                        .font(.title3)
                }
                .accessibilityLabel("Tags de la sélection")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.title3)
                }
                .accessibilityLabel("Supprimer la sélection")
            }
        }
    }
}
