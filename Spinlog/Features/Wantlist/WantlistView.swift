import SwiftUI

/// Même construction que `CollectionView` (recherche, tri, filtre support, sections avec
/// en-têtes et barre de navigation rapide) — sans notion de dossier ni de tag, qui n'existent pas
/// côté wantlist Discogs.
struct WantlistView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var viewModel = WantlistViewModel.shared
    @State private var authManager = DiscogsAuthManager.shared
    @State private var tabCoordinator = TabNavigationCoordinator.shared
    @State private var premiumStore = PremiumStore.shared
    @State private var itemPendingDeletion: WantlistItem? = nil
    @State private var itemForAlert: WantlistItem? = nil
    @State private var showingPremiumSheet = false
    @State private var showingTagFilterSheet = false
    @State private var tagStore = TagStore.shared
    @State private var alertStore = WantlistAlertStore.shared
    @AppStorage("wantlistDisplayMode") private var displayMode: LibraryDisplayMode = .list
    // MARK: - Sélection multiple (suppression en lot), tous modes, à l'image de
    // Collection — sans Déplacer/Tag, qui n'ont pas de sens côté wantlist.
    @State private var isSelecting = false
    @State private var selectedItemIds: Set<Int> = []
    @State private var isBulkProcessing = false
    @State private var showingBulkDeleteConfirmation = false
    /// Clé (`section.key`) de la section actuellement épinglée en haut, mesurée via
    /// `SectionHeaderOffsetKey` — pour la pastille de position de `SectionIndexBar`.
    @State private var currentSectionKey: String? = nil
    /// Nom de la zone de défilement dans laquelle les en-têtes de section rapportent leur
    /// position (voir `reportingSectionOffset`) : un seul nom suffit pour le mode Liste et le mode
    /// Mosaïque, mutuellement exclusifs (`displayMode`).
    private static let sectionsCoordinateSpace = "wantlistSections"

    /// Même formule que `LibraryCarouselView.isRegularDisplay`, voir le commentaire sur
    /// `CollectionView.isRegularDisplay`.
    private var isRegularDisplay: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular
    }

    private func requestAlertSheet(for item: WantlistItem) {
        if premiumStore.isPremium {
            itemForAlert = item
        } else {
            showingPremiumSheet = true
        }
    }

    private func presentPendingAlertIfPossible() {
        guard let releaseId = tabCoordinator.pendingWantlistAlertReleaseId,
              let item = viewModel.items.first(where: { $0.id == releaseId }) else { return }
        tabCoordinator.pendingWantlistAlertReleaseId = nil
        requestAlertSheet(for: item)
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
                    Divider().overlay(Color.appSeparator)
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
    private var trailingToolbarMenu: some View {
        Menu {
            Button {
                withAnimation {
                    isSelecting = true
                }
            } label: {
                Label("Sélectionner", systemImage: "checkmark.circle")
            }
            Divider().overlay(Color.appSeparator)

            LibrarySortMenu(
                sortOption: $viewModel.sortOption,
                sortAscending: $viewModel.sortAscending,
                availableOptions: CollectionSortOption.allCases.filter { $0 != .shelf }
            )
            filterMenu
            LibraryDisplayModeMenu(displayMode: $displayMode)
        } label: {
            Image(systemName: "ellipsis")
        }
    }

    @ViewBuilder
    private var mainView: some View {
        content
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Wantlist")
            .navigationSubtitle(navigationSubtitle)
            .navigationBarTitleDisplayMode(.large)
            .serifNavigationTitle()
                        .searchDestinations()
            .scrollDismissesKeyboard(.immediately)
    }

    var body: some View {
        mainView
            .toolbar {
                if isSelecting {
                    finishLibrarySelectionToolbarItem(isSelecting: $isSelecting, selectedItemIds: $selectedItemIds)
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
                // Plein hauteur d'emblée, comme « Mon exemplaire » : la feuille est longue (en-tête,
                // saisie, marché, jauge, pastilles) et un cran moyen coupait la saisie du prix.
                WantlistAlertSheet(item: item)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: tabCoordinator.pendingWantlistAlertReleaseId, initial: true) {
                presentPendingAlertIfPossible()
            }
            .onChange(of: viewModel.items.count) {
                presentPendingAlertIfPossible()
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
            // Résultat d'une action (retrait, ajout à la collection…) : voir `messageAlert`.
            .messageAlert(message: Binding(
                get: { viewModel.actionMessage },
                set: { viewModel.actionMessage = $0 }
            ))

    }

    private func toggleSelection(_ item: WantlistItem) {
        toggleLibrarySelection(item, selectedItemIds: &selectedItemIds)
    }

    /// Éléments actuellement sélectionnés, dans leur ordre d'apparition (pas celui, non garanti,
    /// de `Set`) — surtout utile pour un message de confirmation stable.
    private var selectedItems: [WantlistItem] {
        selectedLibraryItems(sections: viewModel.sections, selectedItemIds: selectedItemIds)
    }

    /// Barre d'action en lot façon app Fichiers : une seule icône (corbeille), la wantlist ne
    /// supportant pas de déplacement/tag en lot. Remplace la barre d'onglets pendant la sélection
    /// (masquée via `.toolbar(.hidden, for: .tabBar)`), grisée tant qu'aucun élément n'est
    /// sélectionné plutôt que masquée entièrement.
    @ViewBuilder
    private var bulkActionsBar: some View {
        LibraryBulkActionsBar(isSelecting: isSelecting, isEmpty: selectedItemIds.isEmpty, isProcessing: isBulkProcessing) {
            Button(role: .destructive) {
                showingBulkDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.title3)
            }
        }
    }


    /// Nombre total d'éléments de la wantlist — valeur brute chargée (pas de notion de dossier
    /// ici), affichée sous le titre comme pour la Collection.
    private var navigationSubtitle: String {
        // Voir le même commentaire dans CollectionView : un sous-titre vide pendant le chargement
        // puis non vide une fois les données arrivées fait basculer la barre de navigation d'une
        // à deux lignes, décalant le grand titre pile au moment où le squelette laisse place au
        // contenu réel. Un texte de substitution dès le squelette réserve la place.
        guard !viewModel.items.isEmpty else { return isShowingSkeleton ? "…" : "" }
        let total = viewModel.items.count
        if viewModel.hasActiveFilters {
            let filteredCount = viewModel.sections.flatMap(\.items).count
            return String(localized: "\(filteredCount)/\(total) éléments")
        }
        return String(localized: "\(total) éléments")
    }

    @ViewBuilder
    private var wantlistViewCarousel: some View {
        LibraryCarouselView<WantlistItem>(
            sections: viewModel.sections,
            indexEntries: viewModel.indexEntries,
            indexToken: { viewModel.indexToken(for: $0) },
            isSelecting: isSelecting,
            selectedItemIds: selectedItemIds,
            onToggleSelection: { toggleSelection($0) },
            onLoadMore: { await viewModel.loadMoreIfNeeded(current: $0) },
            secondaryBadge: { item in
                guard !isSelecting, let alert = alertStore.alert(for: item.id) else { return AnyView(EmptyView()) }
                return AnyView(
                    HStack(spacing: 4) {
                        Image(systemName: alert.isTriggered ? "bell.badge.fill" : "bell.fill")
                            .font(.inlineIcon)
                        Text("≤ \(alert.targetPrice.formatted(.currency(code: alert.currency)))")
                            .font(isRegularDisplay ? .footnote.bold() : .caption2.bold())
                    }
                    .foregroundStyle(alert.isTriggered ? Color.gainPositive : Color.spinlogPink)
                    .padding(.horizontal, isRegularDisplay ? 10 : 8)
                    .padding(.vertical, isRegularDisplay ? 4 : 3)
                    .background(
                        alert.isTriggered ? Color.gainPositive.opacity(0.12) : Color.spinlogPinkBadge,
                        in: Capsule()
                    )
                    .padding(.top, 2)
                )
            },
            coverOverlay: { item in
                AnyView(
                    CoverAlertBellButton(
                        title: item.basicInformation.title,
                        alert: alertStore.alert(for: item.id),
                        isRegularDisplay: isRegularDisplay
                    ) {
                        requestAlertSheet(for: item)
                    }
                )
            },
            contextMenuContent: { item in wantlistCarouselContextMenu(for: item) }
        )
    }

    /// Menu de l'appui long sur une pochette du carrousel : mêmes actions que le balayage de la liste
    /// (qui n'existe pas hors `List` sur iOS 26). Retrait et passage en collection sont masqués quand
    /// les données sont périmées hors ligne, comme les balayages.
    private func wantlistCarouselContextMenu(for item: WantlistItem) -> AnyView {
        let alert = alertStore.alert(for: item.id)
        return AnyView(
            Group {
                Button {
                    requestAlertSheet(for: item)
                } label: {
                    Label(
                        alert != nil ? "Modifier l'alerte prix" : "Définir une alerte prix",
                        systemImage: alert != nil ? "bell.badge.fill" : "bell"
                    )
                }

                if !viewModel.isOfflineAndStale {
                    Button {
                        Task { await viewModel.beginMoveToCollection(item) }
                    } label: {
                        Label("Vers la collection", systemImage: "square.stack.fill")
                    }

                    Button(role: .destructive) {
                        itemPendingDeletion = item
                    } label: {
                        Label("Supprimer de la wantlist", systemImage: "trash")
                    }
                }
            }
        )
    }

    @ViewBuilder
    private var wantlistViewGrid: some View {
        LibraryMosaicView<WantlistItem>(
            sections: viewModel.sections,
            isLoading: isShowingSkeleton,
            indexToken: { viewModel.indexToken(for: $0) },
            displayTitle: { viewModel.displayTitle(for: $0) },
            headerArtists: { viewModel.headerArtists(for: $0) },
            hasVerticalIndexBar: viewModel.indexEntries.count > 1,
            sectionsCoordinateSpace: Self.sectionsCoordinateSpace,
            isSelecting: isSelecting,
            selectedItemIds: selectedItemIds,
            onToggleSelection: { toggleSelection($0) },
            onLoadMore: { await viewModel.loadMoreIfNeeded(current: $0) },
            cornerBadges: { item in
                let alert = alertStore.alert(for: item.id)
                return AnyView(
                    Color.clear
                        .overlay(alignment: .bottomTrailing) {
                            if let alert {
                                Image(systemName: alert.isTriggered ? "bell.badge.fill" : "bell.fill")
                                    .font(.coverCornerBadge)
                                    .foregroundStyle(alert.isTriggered ? Color.gainPositive : Color.spinlogPink)
                                    .padding(4)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .padding(4)
                            }
                        }
                )
            },
            contextMenuContent: { item in
                let alert = alertStore.alert(for: item.id)
                return AnyView(
                    Button {
                        requestAlertSheet(for: item)
                    } label: {
                        Label(
                            alert != nil ? "Modifier l'alerte prix" : "Définir une alerte prix",
                            systemImage: alert != nil ? "bell.badge.fill" : "bell"
                        )
                    }
                )
            }
        )
    }

    /// Barre de navigation rapide, en overlay sur la vue qui défile effectivement (liste ou
    /// grille) — voir le commentaire au point d'appel.
    @ViewBuilder
    private func indexBarOverlay(proxy: ScrollViewProxy) -> some View {
        LibraryIndexBarOverlay(
            indexEntries: viewModel.indexEntries,
            currentSectionKey: currentSectionKey,
            sections: viewModel.sections,
            indexToken: { viewModel.indexToken(for: $0) },
            proxy: proxy
        )
    }

    @ViewBuilder
    private var wantlistViewList: some View {
        LibraryListView<WantlistItem>(
            sections: viewModel.sections,
            isLoading: isShowingSkeleton,
            skeletonLineCount: 2,
            skeletonCoverSize: WantlistRow.coverSize,
            indexToken: { viewModel.indexToken(for: $0) },
            displayTitle: { viewModel.displayTitle(for: $0) },
            headerArtists: { viewModel.headerArtists(for: $0) },
            hasActiveFilters: viewModel.hasActiveFilters,
            activeFiltersBar: {
                AnyView(
                    LibraryActiveFiltersBar(
                        selectedFormat: $viewModel.selectedFormat,
                        onClearAll: viewModel.clearFilters
                    )
                )
            },
            sectionsCoordinateSpace: Self.sectionsCoordinateSpace,
            hasVerticalIndexBar: viewModel.indexEntries.count > 1,
            isSelecting: isSelecting,
            selectedItemIds: selectedItemIds,
            onToggleSelection: { toggleSelection($0) },
            rowLabel: { item in
                AnyView(
                    WantlistRow(
                        item: item,
                        onAlertTap: { requestAlertSheet(for: item) },
                        isSelecting: isSelecting,
                        isSelected: selectedItemIds.contains(item.id)
                    )
                )
            },
            leadingSwipeActions: { item in
                guard !viewModel.isOfflineAndStale else { return AnyView(EmptyView()) }
                return AnyView(
                    Button {
                        Task { await viewModel.beginMoveToCollection(item) }
                    } label: {
                        Label("Vers la collection", systemImage: "square.stack.fill")
                    }
                    .tint(Color.spinlogPink)
                )
            },
            trailingSwipeActions: { item in
                guard !viewModel.isOfflineAndStale else { return AnyView(EmptyView()) }
                return AnyView(
                    Group {
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
                )
            },
            onLoadMore: { await viewModel.loadMoreIfNeeded(current: $0) },
            onRefresh: {
                await viewModel.refresh()
                Task { await WantlistAlertStore.shared.checkAlerts() }
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        if !authManager.isAuthenticated {
            LoginPromptView(message: String(localized: "Connecte-toi à Discogs pour voir ta wantlist."))
        } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
            ScrollView {
                ContentUnavailableView {
                    Label("Erreur", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Réessayer") {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.glassProminent)
                }
                    .frame(maxWidth: .infinity, minHeight: 400)
            }
            .libraryRefreshable {
                await viewModel.refresh()
            }
        } else if viewModel.items.isEmpty && !viewModel.isLoading {
            ScrollView {
                LibraryEmptyState(
                    title: "Wantlist vide",
                    message: "Ajoute des disques que tu recherches depuis la recherche ou le scan.",
                    symbol: "heart.fill"
                ) {
                    Button("Rechercher un disque") {
                        TabNavigationCoordinator.shared.selectedTab = .search
                    }
                    .buttonStyle(.glassProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 400)
            }
            .libraryRefreshable {
                await viewModel.refresh()
            }
        } else if viewModel.sections.isEmpty && !isShowingSkeleton {
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
                VStack(spacing: 0) {
                    if viewModel.isOfflineAndStale {
                        OfflineBannerView(
                            lastSyncDate: OfflineDownloadManager.shared.lastSyncDate,
                            itemCount: OfflineDownloadManager.shared.offlineItemCount
                        )
                    }

                    switch displayMode {
                    case .carousel:
                        // Voir le commentaire dans `CollectionView` sur le même habillage
                        // `GeometryReader` + `ScrollView` vertical, nécessaire même si
                        // `LibraryCarouselView` ne défile lui-même qu'à l'horizontale.
                        GeometryReader { geo in
                            ScrollView(.vertical, showsIndicators: false) {
                                Group {
                                    if isShowingSkeleton {
                                        LibraryCarouselSkeletonContent(containerSize: geo.size, actionButtonCount: 1)
                                    } else {
                                        wantlistViewCarousel
                                    }
                                }
                                // `alignment: .top` : voir le même commentaire dans `CollectionView`.
                                .frame(minHeight: geo.size.height, alignment: .top)
                            }
                            // Rebond toujours actif : voir `LibraryListView`.
                            .scrollBounceBehavior(.always)
                        }
                    case .grid:
                        wantlistViewGrid
                            // Voir `SectionIndexBar.measuredHeight` et le commentaire dans
                            // `CollectionView` : ancré en bas, la zone sous le grand titre restant
                            // stable par le bas pendant le défilement.
                            .overlay(alignment: .bottomTrailing) { indexBarOverlay(proxy: proxy) }
                    case .list:
                        wantlistViewList
                            .overlay(alignment: .bottomTrailing) { indexBarOverlay(proxy: proxy) }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.indexEntries.count > 1)
                // Section actuellement épinglée en haut, pour la pastille de position de
                // `SectionIndexBar` : ne déclenche un nouveau rendu que lorsqu'elle change
                // réellement, pas à chaque image du défilement (voir `currentSectionKey`).
                .onPreferenceChange(SectionHeaderOffsetKey.self) { candidate in
                    let topKey = candidate?.key
                    if topKey != currentSectionKey { currentSectionKey = topKey }
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

    /// Vrai pendant le chargement initial (aucune donnée du tout) ou le premier tri (données déjà
    /// là, sections pas encore prêtes) : pilote l'affichage du squelette neutre à l'intérieur même
    /// de la hiérarchie de défilement réelle — voir le même principe, plus détaillé, dans
    /// `CollectionView.isShowingSkeleton`. Sans le second cas, un changement de tri/recherche
    /// affichait un bref « Aucun résultat » (sections vides) avant que le calcul détaché termine.
    private var isShowingSkeleton: Bool {
        (viewModel.isLoading && viewModel.items.isEmpty)
            || (viewModel.sections.isEmpty && viewModel.isComputingSections
                && viewModel.searchText.isEmpty && !viewModel.hasActiveFilters)
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
                "Supprimer \(selectedCount) éléments ?",
                isPresented: showingBulkDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    onBulkDelete()
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Cette action retire définitivement ces éléments de ta wantlist Discogs.")
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
                    Text("Veux-tu retirer « \(item.basicInformation.title) » de ta wantlist Discogs ?")
                }
            }
    }
}
