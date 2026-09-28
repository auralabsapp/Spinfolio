import SwiftUI

/// Même construction que `CollectionView` (recherche, tri, filtres tag/support, sections avec
/// en-têtes et barre de navigation rapide) — sans notion de dossier, qui n'existe pas côté
/// wantlist Discogs.
struct WantlistView: View {
    @State private var viewModel = WantlistViewModel()
    @State private var authManager = DiscogsAuthManager.shared
    @State private var tagStore = TagStore.shared

    var body: some View {
        content
            .navigationTitle("Wantlist")
            .navigationSubtitle(navigationSubtitle)
            .searchDestinations()
            .searchable(text: $viewModel.searchText, prompt: "Rechercher dans ta wantlist")
            .toolbar {
                if !viewModel.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 8) {
                            Menu {
                                if viewModel.hasActiveFilters {
                                    Button(role: .destructive) {
                                        viewModel.clearFilters()
                                    } label: {
                                        Label("Effacer les filtres", systemImage: "xmark.circle")
                                    }
                                    Divider()
                                }

                                let tags = tagStore.allTags
                                if !tags.isEmpty {
                                    Menu {
                                        Button("Tous les tags") {
                                            viewModel.selectedTag = nil
                                        }
                                        ForEach(tags, id: \.self) { tag in
                                            Button {
                                                viewModel.selectedTag = (viewModel.selectedTag == tag ? nil : tag)
                                            } label: {
                                                HStack {
                                                    Text(tag)
                                                    if viewModel.selectedTag == tag {
                                                        Spacer()
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }
                                    } label: {
                                        Label(
                                            viewModel.selectedTag != nil ? "Tag : \(viewModel.selectedTag!)" : "Filtrer par tag",
                                            systemImage: "tag"
                                        )
                                    }
                                }

                                let formats = viewModel.availableFormats
                                if !formats.isEmpty {
                                    Menu {
                                        Button("Tous les formats") {
                                            viewModel.selectedFormat = nil
                                        }
                                        ForEach(formats, id: \.self) { format in
                                            Button {
                                                viewModel.selectedFormat = (viewModel.selectedFormat == format ? nil : format)
                                            } label: {
                                                HStack {
                                                    Text(format)
                                                    if viewModel.selectedFormat == format {
                                                        Spacer()
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }
                                    } label: {
                                        Label(
                                            viewModel.selectedFormat != nil ? "Format : \(viewModel.selectedFormat!)" : "Filtrer par format",
                                            systemImage: "square.stack.3d.up"
                                        )
                                    }
                                }
                            } label: {
                                Label(
                                    "Filtrer",
                                    systemImage: viewModel.hasActiveFilters
                                        ? "line.3.horizontal.decrease.circle.fill"
                                        : "line.3.horizontal.decrease.circle"
                                )
                            }

                            Menu {
                                Picker("Trier par", selection: $viewModel.sortOption) {
                                    ForEach(CollectionSortOption.allCases) { option in
                                        Label(option.rawValue, systemImage: option.systemImage).tag(option)
                                    }
                                }
                            } label: {
                                Label(viewModel.sortOption.rawValue, systemImage: viewModel.sortOption.systemImage)
                            }
                        }
                    }
                }
            }
            .confirmationDialog(
                "Ajouter dans quel dossier ?",
                isPresented: Binding(
                    get: { viewModel.itemAwaitingFolderChoice != nil },
                    set: { if !$0 { viewModel.itemAwaitingFolderChoice = nil } }
                ),
                presenting: viewModel.itemAwaitingFolderChoice
            ) { item in
                ForEach(viewModel.folders) { folder in
                    Button("\(folder.name) (\(folder.count))") {
                        Task { await viewModel.confirmMoveToCollection(item, folderId: folder.id) }
                    }
                }
                Button("Annuler", role: .cancel) {}
            }
            .task(id: authManager.isAuthenticated) {
                if authManager.isAuthenticated {
                    await viewModel.load()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .networkConnectionRestored)) { _ in
                Task { await viewModel.silentRefreshIfNeeded() }
            }
    }

    /// Nombre total d'éléments de la wantlist — valeur brute chargée (pas de notion de dossier
    /// ici), affichée sous le titre comme pour la Collection.
    private var navigationSubtitle: String {
        guard !viewModel.items.isEmpty else { return "" }
        let count = viewModel.items.count
        return count == 1 ? "1 élément" : "\(count) éléments"
    }

    @ViewBuilder
    private var content: some View {
        if !authManager.isAuthenticated {
            LoginPromptView(message: "Connecte-toi à Discogs pour voir ta wantlist.")
        } else if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
            ContentUnavailableView("Erreur", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if viewModel.items.isEmpty {
            ContentUnavailableView(
                "Wantlist vide",
                systemImage: "heart",
                description: Text("Ajoute des disques que tu recherches depuis la recherche ou le scan.")
            )
        } else if viewModel.sections.isEmpty {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else {
            ScrollViewReader { proxy in
                ZStack(alignment: .trailing) {
                    VStack(spacing: 0) {
                        if viewModel.isOfflineAndStale {
                            OfflineBannerView()
                        }

                        if viewModel.hasActiveFilters {
                            LibraryActiveFiltersBar(
                                selectedTag: $viewModel.selectedTag,
                                selectedFormat: $viewModel.selectedFormat,
                                onClearAll: viewModel.clearFilters
                            )
                        }

                        List {
                            ForEach(viewModel.sections, id: \.key) { section in
                                Section(header: LibrarySectionHeader(
                                    token: viewModel.indexToken(for: section),
                                    title: viewModel.displayTitle(for: section),
                                    count: section.items.count
                                )) {
                                    ForEach(section.items) { item in
                                        NavigationLink(value: SearchDestination.release(item.id, coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb)) {
                                            WantlistRow(item: item)
                                        }
                                        .task { await viewModel.loadMoreIfNeeded(current: item) }
                                        .swipeActions(edge: .trailing) {
                                            if !viewModel.isOfflineAndStale {
                                                Button(role: .destructive) {
                                                    Task { await viewModel.remove(item) }
                                                } label: {
                                                    Label("Retirer", systemImage: "trash")
                                                }
                                            }
                                        }
                                        .swipeActions(edge: .leading) {
                                            if !viewModel.isOfflineAndStale {
                                                Button {
                                                    Task { await viewModel.beginMoveToCollection(item) }
                                                } label: {
                                                    Label("Vers la collection", systemImage: "square.stack.fill")
                                                }
                                                .tint(.accentColor)
                                            }
                                        }
                                    }
                                }
                                .id(section.key)
                            }
                        }
                        .listStyle(.plain)
                        .listSectionSpacing(.compact)
                        .safeAreaInset(edge: .trailing) {
                            if viewModel.indexEntries.count > 1 {
                                Color.clear.frame(width: 24)
                            }
                        }
                    }

                    if viewModel.indexEntries.count > 1 {
                        SectionIndexBar(entries: viewModel.indexEntries) { sectionKey in
                            proxy.scrollTo(sectionKey, anchor: .top)
                        }
                        .padding(.trailing, 4)
                    }
                }
                .onChange(of: viewModel.sortOption) {
                    withAnimation { proxy.scrollTo(viewModel.sections.first?.key, anchor: .top) }
                }
                .onChange(of: viewModel.selectedTag) {
                    withAnimation { proxy.scrollTo(viewModel.sections.first?.key, anchor: .top) }
                }
                .onChange(of: viewModel.selectedFormat) {
                    withAnimation { proxy.scrollTo(viewModel.sections.first?.key, anchor: .top) }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        WantlistView()
    }
}
