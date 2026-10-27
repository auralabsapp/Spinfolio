import SwiftUI

/// Menu « … » de la barre d'outils de la Collection : disque au hasard (iPad), sélection,
/// dossier, tri, filtres et mode d'affichage. Extrait de `CollectionView` ; l'état reste dans
/// la vue et le view model, passés explicitement.
struct CollectionOptionsMenu: View {
    @Bindable var viewModel: CollectionViewModel
    @Binding var displayMode: LibraryDisplayMode
    @Binding var isSelecting: Bool
    @Binding var selectedItemIds: Set<Int>
    /// Sur iPad uniquement : l'icône directe est retirée de la barre pour laisser la place à la
    /// barre d'onglets flottante. Sur iPhone, elle est déjà dans la barre d'outils.
    let showsRandomButton: Bool
    let currentFolderName: String
    let hasTags: Bool
    let onPickRandom: () -> Void
    let onShowTagFilter: () -> Void

    var body: some View {
        Menu {
            if showsRandomButton {
                Button(action: onPickRandom) {
                    Label("Disque au hasard", systemImage: "shuffle")
                }
                .disabled(viewModel.display.visibleItemCount == 0)
            }

            Button {
                withAnimation {
                    isSelecting.toggle()
                    if !isSelecting {
                        selectedItemIds.removeAll()
                    }
                }
            } label: {
                Label(isSelecting ? "Terminé" : "Sélectionner", systemImage: isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
            }

            Divider().overlay(Color.appSeparator)

            foldersMenu
            LibrarySortMenu(sortOption: Bindable(viewModel.display).sortOption, sortAscending: Bindable(viewModel.display).sortAscending)
            filterMenu
            LibraryDisplayModeMenu(displayMode: $displayMode)
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Options")
    }

    @ViewBuilder
    private var foldersMenu: some View {
        if viewModel.folders.count > 1 {
            Menu {
                Picker("Dossier", selection: Binding(
                    get: { viewModel.selectedFolderId },
                    set: { newId in if let newId { Task { await viewModel.selectFolder(newId) } } }
                )) {
                    ForEach(viewModel.folders.sorted { $0.count > $1.count }) { folder in
                        Text("\(folder.name) (\(folder.count))")
                            .tag(folder.id)
                    }
                }
            } label: {
                Label("Dossier : \(currentFolderName)", systemImage: viewModel.selectedFolderId == DiscogsConstants.allFolderId ? "folder" : "folder.fill")
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            if viewModel.display.hasActiveFilters {
                Button(role: .destructive) {
                    viewModel.display.clearFilters()
                } label: {
                    Label("Effacer les filtres", systemImage: "xmark.circle")
                }
                Divider().overlay(Color.appSeparator)
            }

            if hasTags {
                Button(action: onShowTagFilter) {
                    Label(tagFilterMenuTitle(viewModel.display.selectedTags), systemImage: "tag")
                }
            }

            let missingFields = viewModel.display.availableMissingFields
            if !missingFields.isEmpty {
                Menu {
                    ForEach(missingFields, id: \.self) { field in
                        Toggle(isOn: Binding(
                            get: { viewModel.display.missingFields.contains(field) },
                            set: { _ in viewModel.display.toggleMissingField(field) }
                        )) {
                            Label {
                                Text(field.title)
                            } icon: {
                                Image(systemName: field.systemImage)
                            }
                        }
                    }
                } label: {
                    Label {
                        viewModel.display.missingFields.isEmpty
                            ? Text("À compléter")
                            : Text("À compléter (\(viewModel.display.missingFields.count))")
                    } icon: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }

            let formats = viewModel.availableFormats
            if !formats.isEmpty {
                Menu {
                    LibraryFormatFilterOptions(formats: formats, selectedFormat: Bindable(viewModel.display).selectedFormat)
                } label: {
                    Label {
                        viewModel.display.selectedFormat.map { Text("Format : \($0)") } ?? Text("Filtrer par format")
                    } icon: {
                        Image(systemName: "square.stack.3d.up")
                    }
                }
            }
        } label: {
            Label(
                "Filtres",
                systemImage: viewModel.display.hasActiveFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
    }
}
