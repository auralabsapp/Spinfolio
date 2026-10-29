import SwiftUI

struct CollectionView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Relie chaque pochette à la fiche qu'elle ouvre (zoom, voir `coverZoomSource`).
    @Namespace private var coverZoom
    @State private var viewModel = CollectionViewModel.shared
    @State private var authManager = DiscogsAuthManager.shared
    @State private var tagStore = TagStore.shared
    @State private var tabCoordinator = TabNavigationCoordinator.shared
    @State private var editingItem: CollectionItem?
    @State private var shelfTargetRelease: Release?
    @AppStorage(DisplayPreferenceKeys.collection) private var displayMode: LibraryDisplayMode = .list
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
    /// Section actuellement épinglée en haut, mesurée via `SectionHeaderOffsetKey` — pour la
    /// pastille de position de `SectionIndexBar`. Lue seulement par la barre d'index (voir
    /// `LibraryCurrentSectionTracker`), jamais par ce `body`.
    @State private var sectionTracker = LibraryCurrentSectionTracker()
    /// Nom de la zone de défilement dans laquelle les en-têtes de section rapportent leur
    /// position (voir `reportingSectionOffset`) : un seul nom suffit pour le mode Liste et le mode
    /// Mosaïque, mutuellement exclusifs (`displayMode`).
    private static let sectionsCoordinateSpace = "collectionSections"

    /// Même formule que `LibraryCarouselView.isRegularDisplay`, nécessaire ici pour que les
    /// closures `secondaryBadge`/`quickActions` passées à `LibraryCarouselView` reproduisent les
    /// mêmes tailles de police/espacements selon le gabarit.
    private var isRegularDisplay: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular
    }

    var body: some View {
        content
            .environment(\.coverZoomNamespace, coverZoom)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Collection")
            .navigationSubtitle(navigationSubtitle)
            .navigationBarTitleDisplayMode(.large)
            .serifNavigationTitle()
            .searchDestinations(coverZoom: coverZoom)
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                if isSelecting {
                    // En mode sélection, la barre d'icônes habituelle s'efface au profit d'une
                    // unique coche pour en sortir. Les actions en lot apparaissent dans la
                    // barre du bas, façon app Fichiers.
                    finishLibrarySelectionToolbarItem(isSelecting: $isSelecting, selectedItemIds: $selectedItemIds)
                } else if !viewModel.folders.isEmpty || !viewModel.items.isEmpty {
                    // Sur iPhone (compact), bouton aléatoire direct dans la barre.
                    // Sur iPad (regular), un seul ToolbarItem pour éviter que la barre supérieure
                    // n'entre en collision avec la barre d'onglets flottante iPadOS (ce qui provoquait
                    // un débordement des onglets et masquait le menu d'options).
                    if horizontalSizeClass == .compact {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                pickRandomAlbum()
                            } label: {
                                Image(systemName: "shuffle")
                            }
                            .accessibilityLabel("Disque au hasard")
                            .disabled(viewModel.display.visibleItemCount == 0)
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        CollectionOptionsMenu(
                            viewModel: viewModel,
                            displayMode: $displayMode,
                            isSelecting: $isSelecting,
                            selectedItemIds: $selectedItemIds,
                            showsRandomButton: horizontalSizeClass == .regular,
                            currentFolderName: currentFolderName,
                            hasTags: !tagStore.allTags.isEmpty,
                            onPickRandom: pickRandomAlbum,
                            onShowTagFilter: { showingTagFilterSheet = true }
                        )
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
                    Task { await viewModel.applyEditedValues(for: item, rating: rating, notes: notes) }
                } onFolderChanged: { item, newFolderId in
                    Task { await viewModel.moveInstance(item, toFolderId: newFolderId) }
                } onDelete: {
                    await viewModel.remove(item)
                } onSaveFailedAfterDismiss: { message in
                    viewModel.actionMessage = message
                }
            }
            .modifier(CollectionDeletionAndBulkDialogs(
                viewModel: viewModel,
                itemPendingDeletion: $itemPendingDeletion,
                showingBulkDeleteConfirmation: $showingBulkDeleteConfirmation,
                pendingMoveFolder: $pendingMoveFolder,
                showingBulkTagManagement: $showingBulkTagManagement,
                isSelecting: $isSelecting,
                selectedItemIds: $selectedItemIds,
                isBulkProcessing: $isBulkProcessing,
                selectedItems: selectedItems
            ))
            .sheet(isPresented: $showingTagFilterSheet) {
                TagFilterSheet(allTags: tagStore.allTags, selectedTags: Bindable(viewModel.display).selectedTags)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }

            .onChange(of: displayMode) {
                // Mode d'affichage mémorisé et synchronisé entre appareils (iCloud, Premium).
                CollectionPreferencesStore.displayModesDidChange()
            }
            .task(id: authManager.isAuthenticated) {
                if authManager.isAuthenticated {
                    await viewModel.loadOnAppear()
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
            // Résultat d'une action (retrait, déplacement…) : voir `messageAlert`.
            .messageAlert(message: Binding(
                get: { viewModel.actionMessage },
                set: { viewModel.actionMessage = $0 }
            ))
    }

    private func pickRandomAlbum() {
        let allItems = viewModel.display.sections.flatMap(\.items)
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

    /// Actions sur un exemplaire, partagées par la liste, la mosaïque et le carrousel.
    private var itemActions: CollectionItemActions {
        CollectionItemActions(
            isPlaying: { activityManager.isPlaying(releaseId: $0.releaseId) },
            showShelf: { item in
                if !premiumStore.isPremium {
                    showingPremiumSheet = true
                } else {
                    shelfTargetRelease = Release(from: item)
                }
            },
            edit: { editingItem = $0 },
            requestDeletion: { itemPendingDeletion = $0 }
        )
    }

    private var currentFolder: CollectionFolder? {
        viewModel.folders.first { $0.id == viewModel.selectedFolderId }
    }

    private var currentFolderName: String {
        currentFolder?.name ?? "Collection"
    }

    @ViewBuilder
    private var collectionViewCarousel: some View {
        // Lu une seule fois pour tout ce passage de rendu plutôt qu'une lecture observée par
        // ligne visible — voir `CollectionViewModel.copyBadgesByItemId`.
        let copyBadges = viewModel.display.copyBadgesByItemId
        LibraryCarouselView<CollectionItem>(
            sections: viewModel.display.sections,
            indexEntries: viewModel.display.indexEntries,
            indexToken: { viewModel.display.indexToken(for: $0) },
            isSelecting: isSelecting,
            selectedItemIds: selectedItemIds,
            onToggleSelection: { toggleSelection($0) },
            onLoadMore: { await viewModel.loadMoreIfNeeded(current: $0) },
            scrollToTrigger: randomScrollTrigger,
            secondaryBadge: { item in
                AnyView(CollectionCarouselBadges(
                    copyBadge: copyBadges[item.id],
                    rating: item.rating,
                    isRegularDisplay: isRegularDisplay
                ))
            },
            quickActions: { item in
                let actions = itemActions
                return AnyView(CollectionCarouselQuickActions(
                    isPlaying: actions.isPlaying(item),
                    isRegularDisplay: isRegularDisplay,
                    onToggleListening: { actions.toggleListening(item) },
                    onShowShelf: { actions.showShelf(item) },
                    onEdit: { actions.edit(item) }
                ))
            },
            contextMenuContent: { item in collectionContextMenu(for: item) }
        )
    }

    private func collectionContextMenu(for item: CollectionItem) -> AnyView {
        AnyView(CollectionItemContextMenu(item: item, actions: itemActions, allowsChanges: !viewModel.isOfflineAndStale))
    }

    private func toggleSelection(_ item: CollectionItem) {
        toggleLibrarySelection(item, selectedItemIds: &selectedItemIds)
    }

    /// Exemplaires actuellement sélectionnés, dans leur ordre d'apparition (pas celui, non
    /// garanti, de `Set`) — surtout utile pour un message de confirmation stable.
    private var selectedItems: [CollectionItem] {
        selectedLibraryItems(sections: viewModel.display.sections, selectedItemIds: selectedItemIds)
    }

    private var bulkActionsBar: some View {
        CollectionBulkActionsBar(
            folders: viewModel.folders,
            isSelecting: isSelecting,
            isEmpty: selectedItemIds.isEmpty,
            isProcessing: isBulkProcessing,
            onMove: { pendingMoveFolder = $0 },
            onManageTags: { showingBulkTagManagement = true },
            onDelete: { showingBulkDeleteConfirmation = true }
        )
    }

    /// Barre de navigation rapide, en overlay sur la vue qui défile effectivement (liste ou
    /// grille) — voir le commentaire au point d'appel.
    @ViewBuilder
    private func indexBarOverlay(proxy: ScrollViewProxy) -> some View {
        LibraryIndexBarOverlay(
            indexEntries: viewModel.display.indexEntries,
            sectionTracker: sectionTracker,
            sections: viewModel.display.sections,
            indexToken: { viewModel.display.indexToken(for: $0) },
            proxy: proxy
        )
    }

    @ViewBuilder
    private var collectionViewList: some View {
        // Lus une seule fois pour tout ce passage de rendu plutôt qu'une lecture observée par
        // ligne visible — voir `CollectionViewModel.copyBadgesByItemId`/`tagsByInstanceId`.
        let copyBadges = viewModel.display.copyBadgesByItemId
        let allTags = viewModel.display.tagsByInstanceId
        LibraryListView<CollectionItem>(
            sections: viewModel.display.sections,
            isLoading: isShowingSkeleton,
            indexToken: { viewModel.display.indexToken(for: $0) },
            displayTitle: { viewModel.display.displayTitle(for: $0) },
            headerArtists: { viewModel.display.headerArtists(for: $0) },
            hasActiveFilters: viewModel.display.hasActiveFilters,
            activeFiltersBar: {
                AnyView(
                    CollectionActiveFiltersBar(display: viewModel.display)
                )
            },
            sectionsCoordinateSpace: Self.sectionsCoordinateSpace,
            hasVerticalIndexBar: viewModel.display.indexEntries.count > 1,
            isSelecting: isSelecting,
            selectedItemIds: selectedItemIds,
            onToggleSelection: { toggleSelection($0) },
            rowLabel: { item in
                AnyView(
                    CollectionRow(
                        item: item,
                        copyBadge: copyBadges[item.id],
                        tags: allTags[item.id] ?? [],
                        isSelecting: isSelecting,
                        isSelected: selectedItemIds.contains(item.id)
                    )
                )
            },
            rowBackground: { item in
                highlightedItemId == item.id ? AnyView(CollectionRandomPickHighlight.row) : AnyView(Color.clear)
            },
            leadingSwipeActions: { item in
                AnyView(CollectionLeadingSwipeActions(item: item, actions: itemActions))
            },
            trailingSwipeActions: { item in
                guard !viewModel.isOfflineAndStale else { return AnyView(EmptyView()) }
                return AnyView(CollectionTrailingSwipeActions(item: item, actions: itemActions))
            },
            contextMenuContent: { item in collectionContextMenu(for: item) },
            onLoadMore: { await viewModel.loadMoreIfNeeded(current: $0) },
            onRefresh: { await viewModel.refresh() }
        )
    }

    /// Sous-titre sous le titre "Collection" (inchangé) : nom du dossier courant + son nombre
    /// d'éléments, tiré de `CollectionFolder.count` (valeur totale Discogs), pas de `items.count`
    /// qui ne reflète que ce qui est déjà chargé par la pagination paresseuse.
    private var navigationSubtitle: String {
        // Un sous-titre vide pendant le chargement (dossiers pas encore connus), puis non vide une
        // fois les données arrivées, fait basculer la barre de navigation d'une à deux lignes et
        // déplace le grand titre au moment précis où le squelette laisse place au contenu réel.
        // Un texte de substitution dès le squelette réserve la place pour que le titre ne bouge
        // plus ensuite.
        guard let currentFolder else { return isShowingSkeleton ? currentFolderName : "" }
        if viewModel.display.hasActiveFilters {
            let filteredCount = viewModel.display.visibleItemCount
            return String(localized: "\(currentFolder.name) · \(filteredCount)/\(currentFolder.count) albums")
        }
        return String(localized: "\(currentFolder.name) · \(currentFolder.count) albums")
    }

    @ViewBuilder
    private var content: some View {

        if let error = viewModel.errorMessage, viewModel.items.isEmpty {
            LibraryErrorState(message: error) { await viewModel.refresh() }
        } else if viewModel.items.isEmpty && !viewModel.isLoading && !viewModel.isAwaitingFirstLoad {
            LibraryEmptyLibraryState(
                title: "Collection vide",
                message: "Ajoute des disques depuis la recherche ou le scan.",
                symbol: "square.stack.fill"
            ) { await viewModel.refresh() }
        } else if viewModel.display.sections.isEmpty && !isShowingSkeleton {
            LibraryNoResultsState(isOfflineAndStale: viewModel.isOfflineAndStale, searchText: viewModel.display.searchText) {
                if viewModel.display.hasActiveFilters {
                    CollectionActiveFiltersBar(display: viewModel.display)
                }
            }
        } else {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    if viewModel.isOfflineAndStale {
                        LibraryOfflineBanner()
                    }

                    switch displayMode {
                    case .carousel:
                        // Contrairement au mode Liste (`List` défile nativement) et au mode
                        // Mosaïque (`LibraryMosaicView` a son propre `ScrollView` vertical),
                        // `LibraryCarouselView` n'a qu'un `ScrollView` horizontal en interne.
                        // Sans aucune vue de défilement verticale dans la hiérarchie, le grand
                        // titre de navigation ne s'affiche pas correctement — il faut ce
                        // `ScrollView` vertical même si son contenu ne défile pas lui-même.
                        // La hauteur disponible est mesurée ICI, avant d'entrer dans le
                        // `ScrollView` : lui donner un `.frame(maxHeight: .infinity)` par
                        // l'intérieur (comme c'était fait dans `LibraryCarouselView`)
                        // pousserait le `ScrollView` à proposer une hauteur de contenu quasi
                        // infinie à son enfant, le rendant démesurément grand.
                        GeometryReader { geo in
                            ScrollView(.vertical, showsIndicators: false) {
                                Group {
                                    if isShowingSkeleton {
                                        LibraryCarouselSkeletonContent(containerSize: geo.size, actionButtonCount: 3)
                                    } else {
                                        collectionViewCarousel
                                    }
                                }
                                // `alignment: .top` : sans ça, l'alignement par défaut (`.center`)
                                // centre tout le bloc (carrousel + barre de navigation rapide)
                                // dans la hauteur mesurée, créant un grand vide entre l'indicateur
                                // de position et la barre plutôt qu'en dessous de celle-ci.
                                .frame(minHeight: geo.size.height, alignment: .top)
                            }
                            // Rebond toujours actif : voir `LibraryListView`.
                            .scrollBounceBehavior(.always)
                        }
                    case .grid:
                        // Lu une seule fois pour tout ce passage de rendu plutôt qu'une lecture
                        // observée par ligne visible — voir `CollectionViewModel.copyBadgesByItemId`.
                        let copyBadges = viewModel.display.copyBadgesByItemId
                        LibraryMosaicView<CollectionItem>(
                            sections: viewModel.display.sections,
                            isLoading: isShowingSkeleton,
                            indexToken: { viewModel.display.indexToken(for: $0) },
                            displayTitle: { viewModel.display.displayTitle(for: $0) },
                            headerArtists: { viewModel.display.headerArtists(for: $0) },
                            hasVerticalIndexBar: viewModel.display.indexEntries.count > 1,
                            sectionsCoordinateSpace: Self.sectionsCoordinateSpace,
                            isSelecting: isSelecting,
                            selectedItemIds: selectedItemIds,
                            onToggleSelection: { toggleSelection($0) },
                            onLoadMore: { await viewModel.loadMoreIfNeeded(current: $0) },
                            borderOverlay: { item in
                                highlightedItemId == item.id ? AnyView(CollectionRandomPickHighlight.cover) : AnyView(EmptyView())
                            },
                            cornerBadges: { item in
                                AnyView(CollectionMosaicCornerBadges(
                                    copyBadge: copyBadges[item.id],
                                    isPlaying: activityManager.isPlaying(releaseId: item.releaseId),
                                    rating: item.rating
                                ))
                            },
                            contextMenuContent: { item in collectionContextMenu(for: item) }
                        )
                        // Attachée directement à la vue qui défile (ici, en grille), ancrée en
                        // bas : voir `SectionIndexBar.measuredHeight` pour la raison (la zone
                        // disponible sous le grand titre de navigation s'agrandit par le haut
                        // pendant le défilement, le bas restant stable).
                        .overlay(alignment: .bottomTrailing) { indexBarOverlay(proxy: proxy) }
                    case .list:
                        collectionViewList
                            .overlay(alignment: .bottomTrailing) { indexBarOverlay(proxy: proxy) }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.display.indexEntries.count > 1)
                // Section actuellement épinglée en haut, pour la pastille de position de
                // `SectionIndexBar` : ne déclenche un nouveau rendu que lorsqu'elle change
                // réellement, pas à chaque image du défilement (voir `LibraryCurrentSectionTracker`).
                .onPreferenceChange(SectionHeaderOffsetKey.self) { candidate in
                    sectionTracker.update(to: candidate?.key)
                }
                .safeAreaInset(edge: .top) {
                    // Mode liste exclu : sa propre `List` intègre déjà la barre de filtres
                    // comme ligne (voir `collectionViewList`).
                    if displayMode != .list, viewModel.display.hasActiveFilters {
                        CollectionActiveFiltersBar(display: viewModel.display)
                    }
                }
                // Changer de critère de tri réordonne la liste : on remonte en haut plutôt que de
                // laisser le scroll à une position qui n'a plus de sens.
                .onChange(of: viewModel.display.sortOption) {
                    withAnimation { proxy.scrollTo(viewModel.display.sections.first?.key, anchor: .top) }
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
                        withAnimation { proxy.scrollTo(viewModel.display.sections.first?.key, anchor: .top) }
                    }
                }
                .onChange(of: randomScrollTrigger) { _, newTrigger in
                    guard let newTrigger, displayMode == .list || displayMode == .grid else { return }
                    withAnimation(.scrollToItem) {
                        proxy.scrollTo(newTrigger.id, anchor: .center)
                    }
                }
            }
        }
    }

    /// Vrai pendant le chargement initial (aucune donnée du tout) ou le premier tri (données déjà
    /// là, sections pas encore prêtes) : pilote l'affichage du squelette neutre à la place d'une
    /// icône de chargement, à l'intérieur même de la hiérarchie de défilement réelle (`List` en
    /// mode Liste, `LibraryMosaicView` en mode Mosaïque, ce `ScrollView` vertical en mode
    /// Carrousel) plutôt que dans une branche à part : reconstruire cette hiérarchie séparément
    /// pour le squelette puis pour le contenu réel la détruisait et la recréait à la bascule, ce
    /// qui faisait disparaître puis réapparaître le grand titre de navigation.
    private var isShowingSkeleton: Bool {
        ((viewModel.isLoading || viewModel.isAwaitingFirstLoad) && viewModel.items.isEmpty)
            || (viewModel.display.sections.isEmpty && viewModel.display.isComputingSections
                && viewModel.display.searchText.isEmpty && !viewModel.display.hasActiveFilters)
    }

}
