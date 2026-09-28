import SwiftUI

struct CollectionView: View {
    @State private var viewModel = CollectionViewModel()
    @State private var authManager = DiscogsAuthManager.shared
    @State private var editingItem: CollectionItem?

    var body: some View {
        content
            .navigationTitle("Collection")
            .searchDestinations()
            .searchable(text: $viewModel.searchText, prompt: "Rechercher dans ta collection")
            .toolbar {
                if !viewModel.folders.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            ForEach(viewModel.folders) { folder in
                                Button {
                                    Task { await viewModel.selectFolder(folder.id) }
                                } label: {
                                    Text("\(folder.name) (\(folder.count))")
                                }
                            }
                        } label: {
                            Label(currentFolderName, systemImage: "chevron.down")
                        }
                    }
                }
                if !viewModel.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Trier par", selection: $viewModel.sortOption) {
                                ForEach(CollectionSortOption.allCases) { option in
                                    Label(option.rawValue, systemImage: option.systemImage).tag(option)
                                }
                            }
                        } label: {
                            Label("Trier", systemImage: "arrow.up.arrow.down")
                        }
                    }
                }
            }
            .sheet(item: $editingItem) { item in
                CollectionItemEditSheet(item: item, fields: viewModel.fields) { rating, notes in
                    viewModel.applyEditedValues(for: item, rating: rating, notes: notes)
                }
            }
            .task(id: authManager.isAuthenticated) {
                if authManager.isAuthenticated {
                    await viewModel.loadFoldersAndItems()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .networkConnectionRestored)) { _ in
                Task { await viewModel.silentRefreshIfNeeded() }
            }
    }

    private var currentFolderName: String {
        viewModel.folders.first { $0.id == viewModel.selectedFolderId }?.name ?? "Collection"
    }

    @ViewBuilder
    private var content: some View {
        if !authManager.isAuthenticated {
            LoginPromptView(message: "Connecte-toi à Discogs pour voir et gérer ta collection.")
        } else if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
            ContentUnavailableView("Erreur", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if viewModel.items.isEmpty {
            ContentUnavailableView(
                "Collection vide",
                systemImage: "square.stack",
                description: Text("Ajoute des disques depuis la recherche ou le scan.")
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

                        List {
                            ForEach(viewModel.sections, id: \.key) { section in
                                Section(header: CollectionSectionHeader(
                                    token: viewModel.indexToken(for: section),
                                    title: viewModel.displayTitle(for: section),
                                    count: section.items.count
                                )) {
                                    ForEach(section.items) { item in
                                        NavigationLink(value: SearchDestination.release(item.releaseId, coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb)) {
                                            CollectionRow(item: item)
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
                                                    editingItem = item
                                                } label: {
                                                    Label("Modifier", systemImage: "pencil")
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
                            // Réserve la place de la barre de navigation rapide pour que les
                            // chevrons et compteurs des lignes/en-têtes ne se retrouvent jamais sous elle.
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
            }
        }
    }
}

/// En-tête sticky sur 2 lignes : le jeton (lettre ou année sur 2 chiffres, cohérent avec la
/// barre de navigation rapide) puis la valeur complète du groupe (artiste, album, mois...).
private struct CollectionSectionHeader: View {
    let token: String
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(token)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
            Spacer()
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 0)
        .padding(.trailing, 4)
    }
}
