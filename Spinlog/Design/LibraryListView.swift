import SwiftUI

/// Mode Liste générique, partagé par la Collection et la Wantlist (via `SortableLibraryItem`) :
/// sections épinglées, squelette de chargement, sélection multiple et navigation rapide A-Z. Les
/// deux écrans partageaient ~150-200 lignes identiques, synchronisées « à la main » via des
/// commentaires qui se renvoyaient l'un à l'autre ; seuls le contenu de chaque ligne
/// (`CollectionRow`/`WantlistRow`) et les actions de balayage diffèrent réellement — d'où les
/// closures `rowLabel`/`leadingSwipeActions`/`trailingSwipeActions`, qui renvoient `AnyView`
/// plutôt qu'un paramètre générique supplémentaire par slot (même choix que `LibraryMosaicView`).
struct LibraryListView<Item: SortableLibraryItem>: View {
    let sections: [(key: String, items: [Item])]
    var isLoading: Bool = false
    /// Nombre de lignes de texte du squelette (voir `SkeletonLibraryRow.lineCount`) : suit le
    /// nombre de lignes réel de `rowLabel` (3 pour `CollectionRow`, 2 pour `WantlistRow`).
    var skeletonLineCount: Int = 3
    /// Taille de la pochette du squelette (voir `SkeletonLibraryRow.coverSize`) : suit la taille
    /// réelle de `rowLabel` (`CollectionRow.coverSize` ou `WantlistRow.coverSize`).
    var skeletonCoverSize: CGFloat = CollectionRow.coverSize
    let indexToken: ((key: String, items: [Item])) -> String
    let displayTitle: ((key: String, items: [Item])) -> String
    let headerArtists: ((key: String, items: [Item])) -> [ReleaseArtist]
    var hasActiveFilters: Bool = false
    /// Bandeau affiché en en-tête de section épinglé quand `hasActiveFilters` — voir
    /// `CollectionView.collectionViewList` pour l'intérêt de cette intégration plutôt qu'un
    /// sibling externe ou un `.safeAreaInset` (ne décroche jamais `.searchable()`).
    var activeFiltersBar: () -> AnyView = { AnyView(EmptyView()) }
    let sectionsCoordinateSpace: String
    let hasVerticalIndexBar: Bool
    var isSelecting: Bool = false
    var selectedItemIds: Set<Int> = []
    var onToggleSelection: ((Item) -> Void)? = nil
    /// Contenu visuel d'une ligne (ex: `CollectionRow(...)`, `WantlistRow(...)`) — le
    /// `NavigationLink` et le calque d'interception du tap en mode sélection restent gérés ici,
    /// communs aux deux écrans.
    let rowLabel: (Item) -> AnyView
    /// `Color.clear` par défaut (pas `nil`, qui restaurerait le fond blanc système par défaut de
    /// la ligne) : laisse le fond crème de la `List` apparaître à travers chaque ligne.
    var rowBackground: (Item) -> AnyView? = { _ in AnyView(Color.clear) }
    var leadingSwipeActions: (Item) -> AnyView = { _ in AnyView(EmptyView()) }
    var trailingSwipeActions: (Item) -> AnyView = { _ in AnyView(EmptyView()) }
    /// Mêmes actions que les balayages, par appui long : seul moyen d'y accéder sur iOS 26 et
    /// avec VoiceOver (voir `LibraryMosaicView.contextMenuContent`).
    var contextMenuContent: (Item) -> AnyView = { _ in AnyView(EmptyView()) }
    let onLoadMore: (Item) async -> Void
    let onRefresh: () async -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        List {
            if hasActiveFilters {
                Section {
                    EmptyView()
                } header: {
                    activeFiltersBar()
                        .textCase(nil)
                }
            }
            if isLoading {
                ForEach(0..<2, id: \.self) { _ in
                    Section {
                        ForEach(0..<4, id: \.self) { _ in
                            SkeletonLibraryRow(lineCount: skeletonLineCount, coverSize: skeletonCoverSize)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        SkeletonSectionHeaderRow()
                    }
                }
            } else {
            ForEach(sections, id: \.key) { section in
                Section(header: LibrarySectionHeader(
                    token: indexToken(section),
                    title: displayTitle(section),
                    count: section.items.count,
                    artists: headerArtists(section)
                )
                    // Même trame que l'en-tête de section en mode Mosaïque (voir
                    // `LibraryMosaicView`), reprise à l'identique. Pas de `.padding(.vertical)`
                    // ici : contrairement à la Mosaïque, le total 2+2 (padding interne de
                    // `LibrarySectionHeader` + ses `.listRowInsets`) est déjà atteint sans
                    // padding vertical supplémentaire à ce niveau.
                    .padding(.horizontal, 2)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.libraryHeaderBackground(for: colorScheme))
                            .padding(.horizontal, -8)
                    }
                    // Pour la pastille de position de `SectionIndexBar` (voir `currentSectionKey`
                    // côté appelant).
                    .reportingSectionOffset(key: section.key, coordinateSpace: sectionsCoordinateSpace)
                ) {
                    ForEach(section.items) { item in
                        row(for: item)
                            .id(item.id)
                            // Resserre les lignes : les marges verticales par défaut de `List`
                            // (~11pt en haut et en bas) ajoutent plus de vide que le contenu de
                            // la ligne lui-même.
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(rowBackground(item))
                            .task { await onLoadMore(item) }
                            .contextMenu(isSelecting ? nil : ContextMenu { contextMenuContent(item) })
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if !isSelecting {
                                    leadingSwipeActions(item)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                if !isSelecting {
                                    trailingSwipeActions(item)
                                }
                            }
                    }
                }
                .id(section.key)
            }
            }
        }
        .coordinateSpace(name: sectionsCoordinateSpace)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .listRowSeparatorTint(Color.appSeparator)
        .listSectionSpacing(.compact)
        .environment(\.defaultMinListHeaderHeight, 0)
        // Rebond toujours actif, même quand la liste est courte et tient entièrement à l'écran :
        // la barre d'onglets réduite par un défilement (voir `tabBarMinimizeBehavior`) ne revient
        // à sa taille normale que par un geste vers le bas, impossible sinon sur une liste courte.
        .scrollBounceBehavior(.always)
        // Tirage vers le bas au sommet : la barre d'onglets réduite revient tout de suite (voir
        // `TabNavigationCoordinator.expandTabBar()`), sans attendre la détection d'iOS.
        .onScrollGeometryChange(for: Bool.self) { @Sendable geo in
            geo.contentOffset.y + geo.contentInsets.top < -TabBarPullThreshold.distance
        } action: { _, isPulled in
            if isPulled { TabNavigationCoordinator.shared.expandTabBar() }
        }
        // Le défileur système partage le même liseré que `SectionIndexBar` sur le bord droit :
        // sans ça, sa barre grise native s'affiche en permanence superposée aux jetons de notre
        // propre barre de navigation rapide.
        .scrollIndicators(.hidden)
        .libraryRefreshable {
            await onRefresh()
        }
        .safeAreaInset(edge: .trailing) {
            if hasVerticalIndexBar {
                Color.clear.frame(width: 28)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSelecting)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedItemIds)
    }

    /// `NavigationLink` toujours présent (même identité avant/pendant/après le mode sélection) :
    /// c'est ce qui permet à la pastille de `rowLabel` d'apparaître/disparaître de façon animée
    /// façon app Fichiers, plutôt qu'un remplacement brut de toute la ligne. En mode sélection, un
    /// calque transparent au-dessus intercepte le tap pour (dé)sélectionner au lieu de naviguer.
    private func row(for item: Item) -> some View {
        let info = item.basicInformation
        return ZStack {
            NavigationLink(value: SearchDestination.release(item.releaseId, coverURL: info.coverImage ?? info.thumb)) {
                rowLabel(item)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("libraryItem-\(item.releaseId)")
            .allowsHitTesting(!isSelecting)
            .accessibilityHidden(isSelecting)

            if isSelecting {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onToggleSelection?(item)
                    }
                    .librarySelectionAccessibility(info: info, isSelected: selectedItemIds.contains(item.id)) {
                        onToggleSelection?(item)
                    }
            }
        }
    }
}
