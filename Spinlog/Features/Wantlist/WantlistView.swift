import SwiftUI

/// Même construction que `CollectionView` (recherche, tri, filtre support, sections avec
/// en-têtes et barre de navigation rapide) — sans notion de dossier ni de tag, qui n'existent pas
/// côté wantlist Discogs.
struct WantlistView: View {
    @State private var viewModel = WantlistViewModel.shared
    @State private var authManager = DiscogsAuthManager.shared
    @State private var tabCoordinator = TabNavigationCoordinator.shared
    @State private var premiumStore = PremiumStore.shared
    @State private var itemPendingDeletion: WantlistItem? = nil
    @State private var itemForAlert: WantlistItem? = nil
    @State private var showingPremiumSheet = false
    @State private var showingTagFilterSheet = false
    @State private var tagStore = TagStore.shared
    @AppStorage("wantlistDisplayMode") private var displayMode: LibraryDisplayMode = .list
    // MARK: - Sélection multiple (suppression en lot), tous modes, à l'image de
    // Collection — sans Déplacer/Tag, qui n'ont pas de sens côté wantlist.
    @State private var isSelecting = false
    @State private var selectedItemIds: Set<Int> = []
    @State private var isBulkProcessing = false
    @State private var showingBulkDeleteConfirmation = false

    private func requestAlertSheet(for item: WantlistItem) {
        if premiumStore.isPremium {
            itemForAlert = item
        } else {
            showingPremiumSheet = true
        }
    }

    @ViewBuilder
    private var sortMenu: some View {
        Menu {
            Picker("Trier par", selection: $viewModel.sortOption) {
                ForEach(CollectionSortOption.allCases.filter { $0 != .shelf }) { option in
                    Label(option.rawValue, systemImage: option.systemImage).tag(option)
                }
            }

            Picker("Sens", selection: $viewModel.sortAscending) {
                Label("Croissant", systemImage: "arrow.up").tag(true)
                Label("Décroissant", systemImage: "arrow.down").tag(false)
            }
        } label: {
            Label("Tri : \(viewModel.sortOption.rawValue)", systemImage: viewModel.sortOption.systemImage)
        }
    }

    @ViewBuilder
    private var filterMenu: some View {
        let formats = viewModel.availableFormats
        if !formats.isEmpty {
            Menu {
                if viewModel.hasActiveFilters {
                    Button(role: .destructive) {
                        viewModel.clearFilters()
                    } label: {
                        Label("Effacer les filtres", systemImage: "xmark.circle")
                    }
                    Divider()
                }

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
                    systemImage: viewModel.selectedFormat != nil
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }
        }
    }

    @ViewBuilder
    private var displayModeMenu: some View {
        Menu {
            Picker("Mode d'affichage", selection: $displayMode) {
                ForEach(LibraryDisplayMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
        } label: {
            Label("Affichage : \(displayMode.title)", systemImage: displayMode.systemImage)
        }
    }

    @ViewBuilder
    private var trailingToolbarMenu: some View {
        Menu {
            Button {
                withAnimation {
                    isSelecting = true
                }
            } label: {
                Label("Sélectionner", systemImage: "checkmark.circle")
            }
            Divider()

            sortMenu
            filterMenu
            displayModeMenu
        } label: {
            Image(systemName: "ellipsis")
        }
    }

    @ViewBuilder
    private var mainView: some View {
        content
            .navigationTitle("Wantlist")
            .navigationSubtitle(navigationSubtitle)
            .navigationBarTitleDisplayMode(.large)
            .searchDestinations()
            .searchable(text: $viewModel.searchText, prompt: "Rechercher dans ta wantlist")
            .scrollDismissesKeyboard(.immediately)
    }

    var body: some View {
        mainView
            .toolbar {
                if isSelecting {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation {
                                isSelecting = false
                                selectedItemIds.removeAll()
                            }
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .accessibilityLabel("Terminer la sélection")
                    }
                } else if !viewModel.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        trailingToolbarMenu
                    }
                }
            }
            .toolbar(isSelecting ? .hidden : .visible, for: .tabBar)
            .safeAreaInset(edge: .bottom) {
                bulkActionsBar
            }
            .sheet(item: $itemForAlert) { item in
                WantlistAlertSheet(item: item)
            }
            .premiumFeaturesSheet(isPresented: $showingPremiumSheet)
            .wantlistDialogs(
                itemPendingDeletion: $itemPendingDeletion,
                itemAwaitingFolderChoice: Binding(
                    get: { viewModel.itemAwaitingFolderChoice },
                    set: { viewModel.itemAwaitingFolderChoice = $0 }
                ),
                showingBulkDeleteConfirmation: $showingBulkDeleteConfirmation,
                selectedCount: selectedItemIds.count,
                folders: viewModel.folders,
                onDelete: { item in
                    Task { await viewModel.remove(item) }
                },
                onBulkDelete: {
                    let targets = selectedItems
                    Task {
                        isBulkProcessing = true
                        await viewModel.removeItems(targets)
                        isBulkProcessing = false
                        withAnimation {
                            isSelecting = false
                            selectedItemIds.removeAll()
                        }
                    }
                },
                onConfirmMove: { item, folderId in
                    Task { await viewModel.confirmMoveToCollection(item, folderId: folderId) }
                }
            )
            .task(id: authManager.isAuthenticated) {
                if authManager.isAuthenticated {
                    await viewModel.load()
                    Task { await WantlistAlertStore.shared.checkAlerts() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .networkConnectionRestored)) { _ in
                Task { await viewModel.silentRefreshIfNeeded() }
            }

    }

    private func toggleSelection(_ item: WantlistItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if selectedItemIds.contains(item.id) {
            selectedItemIds.remove(item.id)
        } else {
            selectedItemIds.insert(item.id)
        }
    }

    /// Éléments actuellement sélectionnés, dans leur ordre d'apparition (pas celui, non garanti,
    /// de `Set`) — surtout utile pour un message de confirmation stable.
    private var selectedItems: [WantlistItem] {
        viewModel.sections.flatMap(\.items).filter { selectedItemIds.contains($0.id) }
    }

    /// Barre d'action en lot façon app Fichiers : une seule icône (corbeille), la wantlist ne
    /// supportant pas de déplacement/tag en lot. Remplace la barre d'onglets pendant la sélection
    /// (masquée via `.toolbar(.hidden, for: .tabBar)`), grisée tant qu'aucun élément n'est
    /// sélectionné plutôt que masquée entièrement.
    @ViewBuilder
    private var bulkActionsBar: some View {
        if isSelecting {
            GlassEffectContainer {
                Button(role: .destructive) {
                    showingBulkDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.title3)
                }
                .tint(.primary)
                .disabled(selectedItemIds.isEmpty || isBulkProcessing)
                .opacity(selectedItemIds.isEmpty ? 0.4 : 1)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .glassEffect(.regular.interactive())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
        }
    }

    /// `NavigationLink` toujours présent (même identité avant/pendant/après le mode sélection),
    /// voir le même choix dans `CollectionView.rowContent` : c'est ce qui permet à la pastille de
    /// `WantlistRow` d'apparaître/disparaître de façon animée plutôt qu'un remplacement brut de
    /// toute la ligne. En mode sélection, un calque transparent au-dessus intercepte le tap pour
    /// (dé)sélectionner au lieu de naviguer.
    @ViewBuilder
    private func rowContent(for item: WantlistItem) -> some View {
        ZStack {
            NavigationLink(value: SearchDestination.release(item.id, coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb)) {
                WantlistRow(
                    item: item,
                    onAlertTap: { requestAlertSheet(for: item) },
                    isSelecting: isSelecting,
                    isSelected: selectedItemIds.contains(item.id)
                )
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!isSelecting)

            if isSelecting {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleSelection(item)
                    }
            }
        }
    }

    /// Nombre total d'éléments de la wantlist — valeur brute chargée (pas de notion de dossier
    /// ici), affichée sous le titre comme pour la Collection.
    private var navigationSubtitle: String {
        guard !viewModel.items.isEmpty else { return "" }
        let total = viewModel.items.count
        if viewModel.hasActiveFilters {
            let filteredCount = viewModel.sections.flatMap(\.items).count
            return "\(filteredCount)/\(total) élément\(total == 1 ? "" : "s")"
        }
        return total == 1 ? "1 élément" : "\(total) éléments"
    }

    @ViewBuilder
    private var wantlistViewCarousel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            WantlistCarouselView(
                sections: viewModel.sections,
                indexEntries: viewModel.indexEntries,
                isSelecting: isSelecting,
                selectedItemIds: selectedItemIds,
                onToggleSelection: { toggleSelection($0) },
                onAlertTap: { requestAlertSheet(for: $0) },
                onLoadMore: { await viewModel.loadMoreIfNeeded(current: $0) }
            )
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var wantlistViewGrid: some View {
        WantlistMosaicView(
            sections: viewModel.sections,
            indexToken: { viewModel.indexToken(for: $0) },
            displayTitle: { viewModel.displayTitle(for: $0) },
            hasVerticalIndexBar: viewModel.indexEntries.count > 1,
            isSelecting: isSelecting,
            selectedItemIds: selectedItemIds,
            onToggleSelection: { toggleSelection($0) },
            onAlertTap: { requestAlertSheet(for: $0) },
            onLoadMore: { await viewModel.loadMoreIfNeeded(current: $0) }
        )
    }

    @ViewBuilder
    private var wantlistViewList: some View {
        List {
            // Voir le même commentaire dans CollectionView : en-tête de section épinglé plutôt
            // qu'un sibling externe ou un `.safeAreaInset`, pour ne pas décrocher `.searchable()`
            // tout en restant fixé en haut pendant le défilement (comme l'app Mail).
            if viewModel.hasActiveFilters {
                Section {
                    EmptyView()
                } header: {
                    LibraryActiveFiltersBar(
                        selectedFormat: $viewModel.selectedFormat,
                        onClearAll: viewModel.clearFilters
                    )
                    .textCase(nil)
                }
            }
            ForEach(viewModel.sections, id: \.key) { section in
                Section(header: LibrarySectionHeader(
                    token: viewModel.indexToken(for: section),
                    title: viewModel.displayTitle(for: section),
                    count: section.items.count
                )) {
                    ForEach(section.items) { item in
                        rowContent(for: item)
                            .task { await viewModel.loadMoreIfNeeded(current: item) }
                            .swipeActions(edge: .trailing) {
                                if !isSelecting && !viewModel.isOfflineAndStale {
                                    Button(role: .destructive) {
                                        itemPendingDeletion = item
                                    } label: {
                                        Label("Supprimer", systemImage: "trash")
                                    }
                                    .tint(.red)

                                    Button {
                                        requestAlertSheet(for: item)
                                    } label: {
                                        Label("Alerte", systemImage: "bell")
                                    }
                                    .tint(Color.spinlogPink)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if !isSelecting && !viewModel.isOfflineAndStale {
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
        // Voir le même modifier dans CollectionView : sans ça, `List` impose une
        // hauteur minimale de header généreuse peu importe le contenu réel.
        .environment(\.defaultMinListHeaderHeight, 0)
        // Voir le même modifier dans CollectionView : évite qu'une liste filtrée courte puisse
        // être tirée vers le bas sur une distance excessive par rapport à son contenu réel.
        .scrollBounceBehavior(.basedOnSize)
        // Voir le même modifier dans CollectionView : sans ça, la barre de défilement système
        // s'affiche superposée aux jetons de `SectionIndexBar` sur le bord droit.
        .scrollIndicators(.hidden)
        .refreshable {
            await viewModel.refresh()
            Task { await WantlistAlertStore.shared.checkAlerts() }
        }
        .safeAreaInset(edge: .trailing) {
            if viewModel.indexEntries.count > 1 {
                Color.clear.frame(width: 24)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSelecting)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedItemIds)
    }

    @ViewBuilder
    private var content: some View {
        if !authManager.isAuthenticated {
            LoginPromptView(message: "Connecte-toi à Discogs pour voir ta wantlist.")
        } else if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
            ScrollView {
                ContentUnavailableView("Erreur", systemImage: "exclamationmark.triangle", description: Text(error))
                    .frame(maxWidth: .infinity, minHeight: 400)
            }
            .refreshable {
                await viewModel.refresh()
            }
        } else if viewModel.items.isEmpty {
            ScrollView {
                ContentUnavailableView(
                    "Wantlist vide",
                    systemImage: "heart",
                    description: Text("Ajoute des disques que tu recherches depuis la recherche ou le scan.")
                )
                .frame(maxWidth: .infinity, minHeight: 400)
            }
            .refreshable {
                await viewModel.refresh()
            }
        } else if viewModel.sections.isEmpty {
            VStack(spacing: 0) {
                if viewModel.isOfflineAndStale {
                    OfflineBannerView(
                        lastSyncDate: OfflineDownloadManager.shared.lastSyncDate,
                        itemCount: OfflineDownloadManager.shared.offlineItemCount
                    )
                }
                if viewModel.hasActiveFilters {
                    LibraryActiveFiltersBar(
                        selectedFormat: $viewModel.selectedFormat,
                        onClearAll: viewModel.clearFilters
                    )
                }
                ContentUnavailableView.search(text: viewModel.searchText)
            }
        } else {
            ScrollViewReader { proxy in
                ZStack(alignment: .trailing) {
                    VStack(spacing: 0) {
                        if viewModel.isOfflineAndStale {
                            OfflineBannerView(
                                lastSyncDate: OfflineDownloadManager.shared.lastSyncDate,
                                itemCount: OfflineDownloadManager.shared.offlineItemCount
                            )
                        }

                        switch displayMode {
                        case .carousel:
                            wantlistViewCarousel
                        case .grid:
                            wantlistViewGrid
                        case .list:
                            wantlistViewList
                        }
                    }
                    .safeAreaInset(edge: .top) {
                        // Mode liste exclu : sa propre `List` intègre déjà la barre de filtres
                        // comme ligne (voir `wantlistViewList`).
                        if displayMode != .list, viewModel.hasActiveFilters {
                            LibraryActiveFiltersBar(
                                selectedFormat: $viewModel.selectedFormat,
                                onClearAll: viewModel.clearFilters
                            )
                        }
                    }
                    if (displayMode == .list || displayMode == .grid), viewModel.indexEntries.count > 1 {
                        SectionIndexBar(entries: viewModel.indexEntries) { sectionKey in
                            proxy.scrollTo(sectionKey, anchor: .top)
                        }
                        .padding(.trailing, 4)
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.indexEntries.count > 1)
                .onChange(of: viewModel.sortOption) {
                    withAnimation { proxy.scrollTo(viewModel.sections.first?.key, anchor: .top) }
                }
                // Voir le même commentaire dans CollectionView : pas de scroll-to-top automatique
                // au changement de filtre, cette combinaison List + .searchable() + grand titre
                // s'étant révélée fragile sur chaque variante tentée.
                .onChange(of: tabCoordinator.scrollToTopOfWantlistTrigger) {
                    Task { @MainActor in
                        try? await Task.sleep(for: AppTiming.scrollSettleDelay)
                        withAnimation { proxy.scrollTo(viewModel.sections.first?.key, anchor: .top) }
                    }
                }
            }
        }
    }
}

private extension View {
    func wantlistDialogs(
        itemPendingDeletion: Binding<WantlistItem?>,
        itemAwaitingFolderChoice: Binding<WantlistItem?>,
        showingBulkDeleteConfirmation: Binding<Bool>,
        selectedCount: Int,
        folders: [CollectionFolder],
        onDelete: @escaping (WantlistItem) -> Void,
        onBulkDelete: @escaping () -> Void,
        onConfirmMove: @escaping (WantlistItem, Int) -> Void
    ) -> some View {
        self
            .confirmationDialog(
                "Supprimer \(selectedCount) élément\(selectedCount == 1 ? "" : "s") ?",
                isPresented: showingBulkDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    onBulkDelete()
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Cette action retire définitivement ces éléments de votre wantlist Discogs.")
            }
            .confirmationDialog(
                "Ajouter dans quel dossier ?",
                isPresented: Binding(
                    get: { itemAwaitingFolderChoice.wrappedValue != nil },
                    set: { if !$0 { itemAwaitingFolderChoice.wrappedValue = nil } }
                ),
                presenting: itemAwaitingFolderChoice.wrappedValue
            ) { item in
                ForEach(folders) { folder in
                    Button("\(folder.name) (\(folder.count))") {
                        onConfirmMove(item, folder.id)
                    }
                }
                Button("Annuler", role: .cancel) {}
            }
            .confirmationDialog(
                "Retirer de la wantlist ?",
                isPresented: Binding(
                    get: { itemPendingDeletion.wrappedValue != nil },
                    set: { if !$0 { itemPendingDeletion.wrappedValue = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Retirer de la wantlist", role: .destructive) {
                    if let item = itemPendingDeletion.wrappedValue {
                        onDelete(item)
                    }
                    itemPendingDeletion.wrappedValue = nil
                }
                Button("Annuler", role: .cancel) {
                    itemPendingDeletion.wrappedValue = nil
                }
            } message: {
                if let item = itemPendingDeletion.wrappedValue {
                    Text("Voulez-vous retirer « \(item.basicInformation.title) » de votre wantlist Discogs ?")
                }
            }
    }
}
