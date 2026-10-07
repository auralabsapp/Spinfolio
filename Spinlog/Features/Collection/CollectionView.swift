import SwiftUI

struct CollectionView: View {
    @State private var viewModel = CollectionViewModel.shared
    @State private var authManager = DiscogsAuthManager.shared
    @State private var tagStore = TagStore.shared
    @State private var tabCoordinator = TabNavigationCoordinator.shared
    @State private var editingItem: CollectionItem?
    @State private var shelfTargetRelease: Release?
    @AppStorage("collectionDisplayMode") private var displayMode: LibraryDisplayMode = .list
    @State private var highlightedItemId: Int? = nil
    @State private var randomScrollTrigger: ScrollTargetTrigger? = nil
    @State private var highlightTask: Task<Void, Never>? = nil
    @State private var premiumStore = PremiumStore.shared
    @State private var showingPremiumSheet = false
    @State private var itemPendingDeletion: CollectionItem? = nil
    @State private var showingTagFilterSheet = false
    // MARK: - Sélection multiple (édition en lot), tous modes
    @State private var isSelecting = false
    @State private var selectedItemIds: Set<Int> = []
    @State private var isBulkProcessing = false
    @State private var showingBulkDeleteConfirmation = false
    @State private var showingBulkTagManagement = false
    @State private var pendingMoveFolder: CollectionFolder? = nil
    private var activityManager = NowPlayingActivityManager.shared

    var body: some View {
        content
            .navigationTitle("Collection")
            .navigationSubtitle(navigationSubtitle)
            .navigationBarTitleDisplayMode(.large)
            .searchDestinations()
            .searchable(text: $viewModel.searchText, prompt: "Rechercher dans ta collection")
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                if isSelecting {
                    // En mode sélection, la barre d'icônes habituelle (dossier, "...", disque au
                    // hasard) s'efface au profit d'une unique coche pour en sortir. Les actions en
                    // lot (dossier, tag, corbeille) apparaissent dans la barre du bas, à la place
                    // de la barre d'onglets, façon app Fichiers.
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
                } else if !viewModel.folders.isEmpty || !viewModel.items.isEmpty {
                    // Bouton "..." façon app Fichiers : regroupe Sélectionner, Dossier, Tri,
                    // Filtres et Affichage en un seul point d'entrée plutôt que plusieurs boutons
                    // de toolbar séparés.
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
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

                            Divider()

                            if viewModel.folders.count > 1 {
                                Menu {
                                    ForEach(viewModel.folders.sorted { $0.count > $1.count }) { folder in
                                        Button {
                                            Task { await viewModel.selectFolder(folder.id) }
                                        } label: {
                                            HStack {
                                                Text("\(folder.name) (\(folder.count))")
                                                if folder.id == viewModel.selectedFolderId {
                                                    Spacer()
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Label("Dossier : \(currentFolderName)", systemImage: viewModel.selectedFolderId == DiscogsConstants.allFolderId ? "folder" : "folder.fill")
                                }
                            }

                            Menu {
                                Picker("Trier par", selection: $viewModel.sortOption) {
                                    ForEach(CollectionSortOption.allCases) { option in
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

                            Menu {
                                if viewModel.hasActiveFilters {
                                    Button(role: .destructive) {
                                        viewModel.clearFilters()
                                    } label: {
                                        Label("Effacer les filtres", systemImage: "xmark.circle")
                                    }
                                    Divider()
                                }

                                if !tagStore.allTags.isEmpty {
                                    Button {
                                        showingTagFilterSheet = true
                                    } label: {
                                        Label(tagFilterMenuTitle(viewModel.selectedTags), systemImage: "tag")
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
                                    "Filtres",
                                    systemImage: viewModel.hasActiveFilters
                                        ? "line.3.horizontal.decrease.circle.fill"
                                        : "line.3.horizontal.decrease.circle"
                                )
                            }

                            Menu {
                                Picker("Mode d'affichage", selection: $displayMode) {
                                    ForEach(LibraryDisplayMode.allCases) { mode in
                                        Label(mode.title, systemImage: mode.systemImage)
                                            .tag(mode)
                                    }
                                }
                            } label: {
                                Label("Affichage : \(displayMode.title)", systemImage: displayMode.systemImage)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Options")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            pickRandomAlbum()
                        } label: {
                            Image(systemName: "shuffle")
                        }
                        .accessibilityLabel("Disque au hasard")
                        .disabled(viewModel.sections.flatMap(\.items).isEmpty)
                    }
                }
            }
            .toolbar(isSelecting ? .hidden : .visible, for: .tabBar)
            .safeAreaInset(edge: .bottom) {
                bulkActionsBar
            }
            .sheet(item: $shelfTargetRelease) { release in
                ShelfPlacementView(targetRelease: release)
            }
            .premiumFeaturesSheet(isPresented: $showingPremiumSheet)
            .sheet(item: $editingItem) { item in
                CollectionItemEditSheet(item: item, fields: viewModel.fields, folders: viewModel.folders) { rating, notes in
                    viewModel.applyEditedValues(for: item, rating: rating, notes: notes)
                } onFolderChanged: { item, newFolderId in
                    Task { await viewModel.moveInstance(item, toFolderId: newFolderId) }
                } onDelete: {
                    await viewModel.remove(item)
                }
            }
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
                    Text("Voulez-vous retirer « \(item.basicInformation.title) » de votre collection Discogs ?")
                }
            }
            .confirmationDialog(
                "Supprimer \(selectedItemIds.count) exemplaire\(selectedItemIds.count > 1 ? "s" : "") de la collection ?",
                isPresented: $showingBulkDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    let targets = selectedItems
                    Task {
                        isBulkProcessing = true
                        await viewModel.removeInstances(targets)
                        isBulkProcessing = false
                        withAnimation {
                            isSelecting = false
                            selectedItemIds.removeAll()
                        }
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Cette action retire définitivement ces exemplaires de votre collection Discogs.")
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
                            withAnimation {
                                isSelecting = false
                                selectedItemIds.removeAll()
                            }
                        }
                        pendingMoveFolder = nil
                    }
                }
                Button("Annuler", role: .cancel) {
                    pendingMoveFolder = nil
                }
            }
            .sheet(isPresented: $showingBulkTagManagement) {
                BulkTagManagementSheet(
                    items: selectedItems,
                    onCompletion: {
                        withAnimation {
                            isSelecting = false
                            selectedItemIds.removeAll()
                        }
                    }
                )
            }
            .sheet(isPresented: $showingTagFilterSheet) {
                TagFilterSheet(allTags: tagStore.allTags, selectedTags: $viewModel.selectedTags)
            }

            .task(id: authManager.isAuthenticated) {
                if authManager.isAuthenticated {
                    await viewModel.loadFoldersAndItems()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .networkConnectionRestored)) { _ in
                Task { await viewModel.silentRefreshIfNeeded() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .collectionPreferencesChanged)) { _ in
                Task { await viewModel.handlePreferencesChanged() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .lastConsultedFolderChanged)) { _ in
                Task { await viewModel.handlePreferencesChanged() }
            }
            // Résultat d'une action (retrait, déplacement…) : binding dérivé de la seule
            // `actionMessage`, sans état de présentation séparé qui pourrait se désynchroniser.
            .alert(
                viewModel.actionMessage ?? "",
                isPresented: Binding(
                    get: { viewModel.actionMessage != nil },
                    set: { if !$0 { viewModel.actionMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            }
    }

    private func stopListening(for item: CollectionItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await NowPlayingActivityManager.shared.endActivity(for: item.releaseId)
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

    private func pickRandomAlbum() {
        let allItems = viewModel.sections.flatMap(\.items)
        guard !allItems.isEmpty, let randomItem = allItems.randomElement() else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        randomScrollTrigger = ScrollTargetTrigger(id: randomItem.id)

        withAnimation(.easeInOut(duration: 0.3)) {
            highlightedItemId = randomItem.id
        }

        highlightTask?.cancel()
        highlightTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.8)) {
                    highlightedItemId = nil
                }
            }
        }
    }

    private func triggerListeningLog(for item: CollectionItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        ListeningLogStore.shared.logListening(for: item.releaseId)

        NowPlayingActivityManager.shared.startActivity(
            releaseId: item.releaseId,
            albumTitle: item.basicInformation.title,
            artistName: item.basicInformation.artistNames,
            coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb
        )
    }

    private var currentFolder: CollectionFolder? {
        viewModel.folders.first { $0.id == viewModel.selectedFolderId }
    }

    private var currentFolderName: String {
        currentFolder?.name ?? "Collection"
    }

    /// Sous-titre sous le titre "Collection" (inchangé) : nom du dossier courant + son nombre
    /// d'éléments, tiré de `CollectionFolder.count` (valeur totale Discogs), pas de `items.count`
    /// qui ne reflète que ce qui est déjà chargé par la pagination paresseuse.


    @ViewBuilder
    private var collectionViewCarousel: some View {
        CollectionCarouselView(
            sections: viewModel.sections,
            indexEntries: viewModel.indexEntries,
            copyBadge: { viewModel.copyBadge(for: $0) },
            isPlaying: { activityManager.isPlaying(releaseId: $0) },
            isSelecting: isSelecting,
            selectedItemIds: selectedItemIds,
            onToggleSelection: { toggleSelection($0) },
            onTriggerListening: { triggerListeningLog(for: $0) },
            onStopListening: { stopListening(for: $0) },
            onShelfPlacement: { item in
                if !premiumStore.isPremium {
                    showingPremiumSheet = true
                } else {
                    shelfTargetRelease = Release(from: item)
                }
            },
            onEditItem: { editingItem = $0 },
            onLoadMore: { await viewModel.loadMoreIfNeeded(current: $0) },
            scrollToTrigger: randomScrollTrigger
        )
    }

    @ViewBuilder
    private func collectionRowHighlight(for item: CollectionItem) -> some View {
        if highlightedItemId == item.id {
            Color.spinlogPink.opacity(0.18)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.spinlogPink.opacity(0.6), lineWidth: 1.5)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                )
        }
    }

    /// `NavigationLink` toujours présent (même identité avant/pendant/après le mode sélection) :
    /// c'est ce qui permet à la pastille de `CollectionRow` d'apparaître/disparaître de façon
    /// animée façon app Fichiers, plutôt qu'un remplacement brut de toute la ligne. En mode
    /// sélection, un calque transparent au-dessus intercepte le tap pour (dé)sélectionner au
    /// lieu de naviguer.
    @ViewBuilder
    private func rowContent(for item: CollectionItem) -> some View {
        ZStack {
            NavigationLink(value: SearchDestination.release(item.releaseId, coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb)) {
                CollectionRow(
                    item: item,
                    copyBadge: viewModel.copyBadge(for: item),
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

    private func toggleSelection(_ item: CollectionItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if selectedItemIds.contains(item.id) {
            selectedItemIds.remove(item.id)
        } else {
            selectedItemIds.insert(item.id)
        }
    }

    /// Exemplaires actuellement sélectionnés, dans leur ordre d'apparition (pas celui, non
    /// garanti, de `Set`) — surtout utile pour un message de confirmation stable.
    private var selectedItems: [CollectionItem] {
        viewModel.sections.flatMap(\.items).filter { selectedItemIds.contains($0.id) }
    }

    /// Barre d'actions en lot façon app Fichiers : pile flottante en vrai Liquid Glass
    /// (`glassEffect`) qui remplace la barre d'onglets pendant la sélection (masquée via
    /// `.toolbar(.hidden, for: .tabBar)`), icônes grisées tant qu'aucun exemplaire n'est
    /// sélectionné plutôt que la barre entière qui disparaîtrait.
    @ViewBuilder
    private var bulkActionsBar: some View {
        if isSelecting {
            GlassEffectContainer {
                HStack(spacing: 36) {
                    Menu {
                        ForEach(viewModel.folders.filter { $0.id != DiscogsConstants.allFolderId }) { folder in
                            Button(folder.name) {
                                pendingMoveFolder = folder
                            }
                        }
                    } label: {
                        Image(systemName: "folder")
                            .font(.title3)
                    }

                    Button {
                        showingBulkTagManagement = true
                    } label: {
                        Image(systemName: "tag")
                            .font(.title3)
                    }

                    Button(role: .destructive) {
                        showingBulkDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.title3)
                    }
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



    @ViewBuilder
    private var collectionViewList: some View {
        List {
            // Intégrée comme en-tête de section plutôt qu'en sibling externe ou en
            // `.safeAreaInset` : filtrer le contenu d'une `List` (ajouter/retirer des sections) est
            // son usage normal et ne perturbe jamais `.searchable()`, contrairement à un élément
            // externe qui change le cadre de la liste dans son parent. En en-tête (plutôt qu'une
            // ligne normale), `.listStyle(.plain)` l'épingle nativement en haut pendant le
            // défilement — comme la barre de filtres actifs de l'app Mail — au lieu de défiler
            // avec le contenu.
            if viewModel.hasActiveFilters {
                Section {
                    EmptyView()
                } header: {
                    LibraryActiveFiltersBar(
                        selectedTags: $viewModel.selectedTags,
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
                            .id(item.id)
                            .listRowBackground(collectionRowHighlight(for: item))
                            .task { await viewModel.loadMoreIfNeeded(current: item) }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if !isSelecting {
                                    if activityManager.isPlaying(releaseId: item.releaseId) {
                                        Button {
                                            stopListening(for: item)
                                        } label: {
                                            Label("Stop", systemImage: "stop.fill")
                                        }
                                        .tint(Color(uiColor: .systemGray))
                                    } else {
                                        Button {
                                            triggerListeningLog(for: item)
                                        } label: {
                                            Label("Lecture", systemImage: "play.fill")
                                        }
                                        .tint(Color.spinlogPink)
                                    }

                                    Button {
                                        if !premiumStore.isPremium {
                                            showingPremiumSheet = true
                                        } else {
                                            shelfTargetRelease = Release(from: item)
                                        }
                                    } label: {
                                        Label("Ranger", systemImage: "books.vertical.fill")
                                    }
                                    .tint(.indigo)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                if !isSelecting && !viewModel.isOfflineAndStale {
                                    Button(role: .destructive) {
                                        itemPendingDeletion = item
                                    } label: {
                                        Label("Supprimer", systemImage: "trash.fill")
                                    }
                                    .tint(.red)

                                    Button {
                                        editingItem = item
                                    } label: {
                                        Label("Modifier", systemImage: "pencil")
                                    }
                                    .tint(.orange)
                                }
                            }
                    }
                }
                .id(section.key)
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .environment(\.defaultMinListHeaderHeight, 0)
        // Sans ça, une liste filtrée courte (qui tient entièrement à l'écran) garde le rebond
        // élastique habituel et peut être tirée vers le bas sur une distance excessive, bien
        // au-delà de son contenu réel.
        .scrollBounceBehavior(.basedOnSize)
        // Le défileur système partage le même liseré de 20-24pt que `SectionIndexBar` sur le
        // bord droit : sans ça, sa barre grise native (proportionnelle à la hauteur du contenu,
        // donc parfois très longue) s'affiche en permanence superposée aux jetons de notre propre
        // barre de navigation rapide — visible comme une longue barre verticale "bizarre".
        .scrollIndicators(.hidden)
        .refreshable {
            await viewModel.refresh()
        }
        .safeAreaInset(edge: .trailing) {
            if viewModel.indexEntries.count > 1 {
                Color.clear.frame(width: 24)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSelecting)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedItemIds)
    }

    private var navigationSubtitle: String {
        guard let currentFolder else { return "" }
        if viewModel.hasActiveFilters {
            let filteredCount = viewModel.sections.flatMap(\.items).count
            return "\(currentFolder.name) · \(filteredCount)/\(currentFolder.count) élément\(currentFolder.count == 1 ? "" : "s")"
        }
        return "\(currentFolder.name) · \(currentFolder.count) élément\(currentFolder.count == 1 ? "" : "s")"
    }

    @ViewBuilder
    private var content: some View {

        if !authManager.isAuthenticated {
            LoginPromptView(message: "Connecte-toi à Discogs pour voir et gérer ta collection.")
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
                    "Collection vide",
                    systemImage: "square.stack",
                    description: Text("Ajoute des disques depuis la recherche ou le scan.")
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
                        selectedTags: $viewModel.selectedTags,
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
                            ScrollView(.vertical, showsIndicators: false) {
                                collectionViewCarousel
                                    .padding(.top, 24)
                                    .padding(.bottom, 16)
                            }
                        case .grid:
                            CollectionMosaicView(
                                sections: viewModel.sections,
                                indexToken: { viewModel.indexToken(for: $0) },
                                displayTitle: { viewModel.displayTitle(for: $0) },
                                copyBadge: { viewModel.copyBadge(for: $0) },
                                isPlaying: { activityManager.isPlaying(releaseId: $0) },
                                highlightedItemId: highlightedItemId,
                                hasVerticalIndexBar: viewModel.indexEntries.count > 1,
                                isSelecting: isSelecting,
                                selectedItemIds: selectedItemIds,
                                onToggleSelection: { toggleSelection($0) },
                                onTriggerListening: { triggerListeningLog(for: $0) },
                                onStopListening: { stopListening(for: $0) },
                                onShelfPlacement: { item in
                                    if !premiumStore.isPremium {
                                        showingPremiumSheet = true
                                    } else {
                                        shelfTargetRelease = Release(from: item)
                                    }
                                },
                                onEditItem: { item in
                                    editingItem = item
                                },
                                onDeleteItem: { item in
                                    itemPendingDeletion = item
                                },
                                onLoadMore: { await viewModel.loadMoreIfNeeded(current: $0) }
                            )
                        case .list:
                            collectionViewList
                        }
                    }
                    .safeAreaInset(edge: .top) {
                        // Mode liste exclu : sa propre `List` intègre déjà la barre de filtres
                        // comme ligne (voir `collectionViewList`).
                        if displayMode != .list, viewModel.hasActiveFilters {
                            LibraryActiveFiltersBar(
                                selectedTags: $viewModel.selectedTags,
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
                // Changer de critère de tri réordonne la liste : on remonte en haut plutôt que de
                // laisser le scroll à une position qui n'a plus de sens.
                .onChange(of: viewModel.sortOption) {
                    withAnimation { proxy.scrollTo(viewModel.sections.first?.key, anchor: .top) }
                }
                // Pas de scroll-to-top automatique au changement de filtre (tags/support) : chaque
                // variante tentée (animée, non animée, recréation de liste via `.id()`, forçage de
                // la grande barre de titre) a introduit un bug différent dans cette combinaison
                // précise List + .searchable() + grand titre (flash, titre non resynchronisé,
                // pull-to-refresh trop sensible, vide permanent, barre de recherche décrochée). La
                // liste reste donc où elle est quand on change de filtre.
                .onChange(of: tabCoordinator.scrollToTopOfCollectionTrigger) {
                    Task { @MainActor in
                        try? await Task.sleep(for: AppTiming.scrollSettleDelay)
                        withAnimation { proxy.scrollTo(viewModel.sections.first?.key, anchor: .top) }
                    }
                }
                .onChange(of: randomScrollTrigger) { _, newTrigger in
                    guard let newTrigger, displayMode == .list || displayMode == .grid else { return }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        proxy.scrollTo(newTrigger.id, anchor: .center)
                    }
                }
            }
        }
    }

}
