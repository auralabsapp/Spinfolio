import SwiftUI

struct CollectionView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    /// Clé (`section.key`) de la section actuellement épinglée en haut, mesurée via
    /// `SectionHeaderOffsetKey` — pour la pastille de position de `SectionIndexBar`.
    @State private var currentSectionKey: String? = nil
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
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Collection")
            .navigationSubtitle(navigationSubtitle)
            .navigationBarTitleDisplayMode(.large)
            .serifNavigationTitle()
                        .searchDestinations()
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                if isSelecting {
                    // En mode sélection, la barre d'icônes habituelle s'efface au profit d'une
                    // unique coche pour en sortir. Les actions en lot apparaissent dans la
                    // barre du bas, façon app Fichiers.
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
                            .disabled(viewModel.sections.flatMap(\.items).isEmpty)
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        trailingToolbarMenu
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
                    Text("Veux-tu retirer « \(item.basicInformation.title) » de ta collection Discogs ?")
                }
            }
            .confirmationDialog(
                "Supprimer \(selectedItemIds.count) exemplaires de la collection ?",
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
                Text("Cette action retire définitivement ces exemplaires de ta collection Discogs.")
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


    // MARK: - Menus d'options de la barre d'outils

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

    @ViewBuilder
    private var sortMenu: some View {
        Menu {
            Picker("Trier par", selection: $viewModel.sortOption) {
                ForEach(CollectionSortOption.allCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option)
                }
            }

            Picker("Sens", selection: $viewModel.sortAscending) {
                Label("Croissant", systemImage: "arrow.up").tag(true)
                Label("Décroissant", systemImage: "arrow.down").tag(false)
            }
        } label: {
            Label("Tri : \(viewModel.sortOption.title)", systemImage: viewModel.sortOption.systemImage)
        }
    }

    @ViewBuilder
    private var filterMenu: some View {
        Menu {
            if viewModel.hasActiveFilters {
                Button(role: .destructive) {
                    viewModel.clearFilters()
                } label: {
                    Label("Effacer les filtres", systemImage: "xmark.circle")
                }
                Divider().overlay(Color.appSeparator)
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
    }

    @ViewBuilder
    private var displayModeMenu: some View {
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
    }

    @ViewBuilder
    private var trailingToolbarMenu: some View {
        Menu {
            // Sur iPad uniquement (où l'icône shuffle directe est retirée de la barre pour libérer
            // l'espace nécessaire à la barre d'onglets flottante). Sur iPhone, l'icône est déjà
            // directement accessible dans la barre d'outils.
            if horizontalSizeClass == .regular {
                Button {
                    pickRandomAlbum()
                } label: {
                    Label("Disque au hasard", systemImage: "shuffle")
                }
                .disabled(viewModel.sections.flatMap(\.items).isEmpty)
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
            sortMenu
            filterMenu
            displayModeMenu
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Options")
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
        // Calculé une seule fois pour tout ce passage de rendu plutôt qu'un appel par ligne
        // visible — voir `CollectionViewModel.copyBadges(for:)`.
        let copyBadges = viewModel.copyBadges(for: viewModel.items)
        LibraryCarouselView<CollectionItem>(
            sections: viewModel.sections,
            indexEntries: viewModel.indexEntries,
            indexToken: { viewModel.indexToken(for: $0) },
            isSelecting: isSelecting,
            selectedItemIds: selectedItemIds,
            onToggleSelection: { toggleSelection($0) },
            onLoadMore: { await viewModel.loadMoreIfNeeded(current: $0) },
            scrollToTrigger: randomScrollTrigger,
            secondaryBadge: { item in
                AnyView(
                    HStack(spacing: 8) {
                        if let badge = copyBadges[item.id] {
                            Text(badge)
                                .font(isRegularDisplay ? .footnote.bold() : .caption2.bold())
                                .padding(.horizontal, isRegularDisplay ? 9 : 7)
                                .padding(.vertical, isRegularDisplay ? 3 : 2)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                        }

                        if item.rating > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.inlineIcon)
                                    .foregroundStyle(Color.orange)
                                Text("\(item.rating)")
                                    .font(isRegularDisplay ? .footnote.bold() : .caption2.bold())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 2)
                )
            },
            quickActions: { item in
                AnyView(
                    HStack(spacing: isRegularDisplay ? 16 : 12) {
                        // Écoute en direct (Start / Stop)
                        Button {
                            if activityManager.isPlaying(releaseId: item.releaseId) {
                                stopListening(for: item)
                            } else {
                                triggerListeningLog(for: item)
                            }
                        } label: {
                            Image(systemName: activityManager.isPlaying(releaseId: item.releaseId) ? "stop.fill" : "opticaldisc.fill")
                                .font(.system(size: isRegularDisplay ? 17 : 14, weight: .bold))
                                .foregroundStyle(activityManager.isPlaying(releaseId: item.releaseId) ? .white : Color.spinlogPink)
                                .frame(width: isRegularDisplay ? 46 : 38, height: isRegularDisplay ? 46 : 38)
                                .background(
                                    activityManager.isPlaying(releaseId: item.releaseId) ? Color(uiColor: .systemGray) : Color.spinlogPinkBadge,
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(activityManager.isPlaying(releaseId: item.releaseId) ? Text("Arrêter l'écoute") : Text("J'écoute ce disque sur la platine"))

                        // Où ranger
                        Button {
                            if !premiumStore.isPremium {
                                showingPremiumSheet = true
                            } else {
                                shelfTargetRelease = Release(from: item)
                            }
                        } label: {
                            Image(systemName: "books.vertical.fill")
                                .font(.system(size: isRegularDisplay ? 17 : 14, weight: .semibold))
                                .foregroundStyle(.indigo)
                                .frame(width: isRegularDisplay ? 46 : 38, height: isRegularDisplay ? 46 : 38)
                                .background(Color.indigo.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Où ranger ce disque")

                        // Modifier notes/note
                        Button {
                            editingItem = item
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: isRegularDisplay ? 17 : 14, weight: .semibold))
                                .foregroundStyle(Color.appSecondaryText)
                                .frame(width: isRegularDisplay ? 46 : 38, height: isRegularDisplay ? 46 : 38)
                                .background(Color.primary.opacity(0.06), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Modifier la note et les commentaires")
                    }
                )
            }
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

    /// Barre de navigation rapide, en overlay sur la vue qui défile effectivement (liste ou
    /// grille) — voir le commentaire au point d'appel.
    @ViewBuilder
    private func indexBarOverlay(proxy: ScrollViewProxy) -> some View {
        if viewModel.indexEntries.count > 1 {
            SectionIndexBar(entries: viewModel.indexEntries, currentToken: currentIndexToken) { sectionKey in
                proxy.scrollTo(sectionKey, anchor: .top)
            }
            .padding(.trailing, 4)
            .transition(.opacity)
        }
    }

    /// Jeton de `currentSectionKey` dans la barre de navigation rapide (plusieurs sections —
    /// un artiste par section — peuvent partager le même jeton, leur première lettre commune).
    private var currentIndexToken: String? {
        guard let currentSectionKey,
              let section = viewModel.sections.first(where: { $0.key == currentSectionKey }) else { return nil }
        return viewModel.indexToken(for: section)
    }

    @ViewBuilder
    private var collectionViewList: some View {
        // Calculé une seule fois pour tout ce passage de rendu plutôt qu'un appel par ligne
        // visible — voir `CollectionViewModel.copyBadges(for:)`/`tagsByInstance(for:)`.
        let copyBadges = viewModel.copyBadges(for: viewModel.items)
        let allTags = viewModel.tagsByInstance(for: viewModel.items)
        LibraryListView<CollectionItem>(
            sections: viewModel.sections,
            isLoading: isShowingSkeleton,
            indexToken: { viewModel.indexToken(for: $0) },
            displayTitle: { viewModel.displayTitle(for: $0) },
            headerArtists: { viewModel.headerArtists(for: $0) },
            hasActiveFilters: viewModel.hasActiveFilters,
            activeFiltersBar: {
                AnyView(
                    LibraryActiveFiltersBar(
                        selectedTags: $viewModel.selectedTags,
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
                highlightedItemId == item.id ? AnyView(collectionRowHighlight(for: item)) : AnyView(Color.clear)
            },
            leadingSwipeActions: { item in
                AnyView(
                    Group {
                        if activityManager.isPlaying(releaseId: item.releaseId) {
                            Button {
                                stopListening(for: item)
                            } label: {
                                Label("Arrêter l'écoute", systemImage: "stop.fill")
                            }
                            .tint(Color(uiColor: .systemGray))
                        } else {
                            Button {
                                triggerListeningLog(for: item)
                            } label: {
                                Label("J'écoute", systemImage: "opticaldisc.fill")
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
                )
            },
            trailingSwipeActions: { item in
                guard !viewModel.isOfflineAndStale else { return AnyView(EmptyView()) }
                return AnyView(
                    Group {
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
                )
            },
            onLoadMore: { await viewModel.loadMoreIfNeeded(current: $0) },
            onRefresh: { await viewModel.refresh() }
        )
    }

    private var navigationSubtitle: String {
        // Un sous-titre vide pendant le chargement (dossiers pas encore connus), puis non vide une
        // fois les données arrivées, fait basculer la barre de navigation d'une à deux lignes et
        // déplace le grand titre au moment précis où le squelette laisse place au contenu réel.
        // Un texte de substitution dès le squelette réserve la place pour que le titre ne bouge
        // plus ensuite.
        guard let currentFolder else { return isShowingSkeleton ? currentFolderName : "" }
        if viewModel.hasActiveFilters {
            let filteredCount = viewModel.sections.flatMap(\.items).count
            return String(localized: "\(currentFolder.name) · \(filteredCount)/\(currentFolder.count) éléments")
        }
        return String(localized: "\(currentFolder.name) · \(currentFolder.count) éléments")
    }

    @ViewBuilder
    private var content: some View {

        if !authManager.isAuthenticated {
            LoginPromptView(message: String(localized: "Connecte-toi à Discogs pour voir et gérer ta collection."))
        } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
            ScrollView {
                ContentUnavailableView("Erreur", systemImage: "exclamationmark.triangle", description: Text(error))
                    .frame(maxWidth: .infinity, minHeight: 400)
            }
            .refreshable {
                await viewModel.refresh()
            }
        } else if viewModel.items.isEmpty && !viewModel.isLoading {
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
                        selectedTags: $viewModel.selectedTags,
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
                        }
                    case .grid:
                        // Calculé une seule fois pour tout ce passage de rendu plutôt qu'un appel
                        // par ligne visible — voir `CollectionViewModel.copyBadges(for:)`.
                        let copyBadges = viewModel.copyBadges(for: viewModel.items)
                        LibraryMosaicView<CollectionItem>(
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
                            borderOverlay: { item in
                                if highlightedItemId == item.id {
                                    AnyView(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(Color.spinlogPink, lineWidth: 3)
                                            .shadow(color: Color.spinlogPink.opacity(0.6), radius: 6)
                                    )
                                } else {
                                    AnyView(EmptyView())
                                }
                            },
                            cornerBadges: { item in
                                AnyView(
                                    Color.clear
                                        .overlay(alignment: .topTrailing) {
                                            if let badge = copyBadges[item.id] {
                                                Text(badge)
                                                    .font(.coverCornerBadge)
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 2)
                                                    .background(Color.black.opacity(0.7), in: Capsule())
                                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
                                                    .padding(4)
                                            }
                                        }
                                        .overlay(alignment: .bottomLeading) {
                                            if activityManager.isPlaying(releaseId: item.releaseId) {
                                                HStack(spacing: 3) {
                                                    Image(systemName: "waveform")
                                                        .font(.coverCornerBadge)
                                                        .symbolEffect(.variableColor.iterative.reversing)
                                                }
                                                .foregroundStyle(Color.spinlogPink)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 3)
                                                .background(.ultraThinMaterial, in: Capsule())
                                                .padding(4)
                                            }
                                        }
                                        .overlay(alignment: .bottomTrailing) {
                                            if item.rating > 0 {
                                                HStack(spacing: 1.5) {
                                                    Image(systemName: "star.fill")
                                                        .font(.coverCornerBadge)
                                                        .foregroundStyle(Color.orange)
                                                    Text("\(item.rating)")
                                                        .font(.coverCornerBadge)
                                                        .foregroundStyle(.white)
                                                }
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(Color.black.opacity(0.65), in: Capsule())
                                                .padding(4)
                                            }
                                        }
                                )
                            },
                            contextMenuContent: { item in
                                AnyView(
                                    Group {
                                        if activityManager.isPlaying(releaseId: item.releaseId) {
                                            Button {
                                                stopListening(for: item)
                                            } label: {
                                                Label("Arrêter l'écoute", systemImage: "stop.fill")
                                            }
                                        } else {
                                            Button {
                                                triggerListeningLog(for: item)
                                            } label: {
                                                Label("J'écoute ce disque sur la platine", systemImage: "opticaldisc.fill")
                                            }
                                        }

                                        Button {
                                            if !premiumStore.isPremium {
                                                showingPremiumSheet = true
                                            } else {
                                                shelfTargetRelease = Release(from: item)
                                            }
                                        } label: {
                                            Label("Où ranger", systemImage: "books.vertical.fill")
                                        }

                                        Button {
                                            editingItem = item
                                        } label: {
                                            Label("Modifier la note / notes", systemImage: "pencil")
                                        }

                                        Button(role: .destructive) {
                                            itemPendingDeletion = item
                                        } label: {
                                            Label("Supprimer de la collection", systemImage: "trash")
                                        }
                                    }
                                )
                            }
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
                    // comme ligne (voir `collectionViewList`).
                    if displayMode != .list, viewModel.hasActiveFilters {
                        LibraryActiveFiltersBar(
                            selectedTags: $viewModel.selectedTags,
                            selectedFormat: $viewModel.selectedFormat,
                            onClearAll: viewModel.clearFilters
                        )
                    }
                }
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
        (viewModel.isLoading && viewModel.items.isEmpty)
            || (viewModel.sections.isEmpty && viewModel.isComputingSections
                && viewModel.searchText.isEmpty && !viewModel.hasActiveFilters)
    }

}
