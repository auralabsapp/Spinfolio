import SwiftUI

/// Vue Mosaïque générique, partagée par la Collection et la Wantlist (via `SortableLibraryItem`) :
/// grille de pochettes vinyles carrées sur 4 colonnes, avec en-têtes de sections épinglés (pinned
/// section headers), menu contextuel d'actions rapides et compatibilité totale avec la barre
/// verticale de navigation A-Z. Les deux écrans partageaient ~250 lignes identiques (grille,
/// squelette, cellule, sélection multiple) ; seuls les badges superposés à la pochette et le menu
/// contextuel diffèrent réellement (exemplaires/lecture/note pour la Collection, alerte de prix
/// pour la Wantlist) — d'où les closures `cornerBadges`/`borderOverlay`/`contextMenuContent`, qui
/// renvoient `AnyView` plutôt qu'un paramètre générique supplémentaire par slot.
struct LibraryMosaicView<Item: SortableLibraryItem>: View {
    let sections: [(key: String, items: [Item])]
    /// Chargement initial ou premier tri en cours : affiche des cellules neutres à la place des
    /// vraies pochettes, dans la même grille (voir le commentaire dans `CollectionView.content`
    /// sur l'intérêt de ne pas reconstruire ce `ScrollView` séparément pour le squelette).
    var isLoading: Bool = false
    let indexToken: ((key: String, items: [Item])) -> String
    let displayTitle: ((key: String, items: [Item])) -> String
    let headerArtists: ((key: String, items: [Item])) -> [ReleaseArtist]
    let hasVerticalIndexBar: Bool
    /// Nom de la zone de défilement dans laquelle les en-têtes de section rapportent leur
    /// position (voir `reportingSectionOffset`, pour la pastille de position de
    /// `SectionIndexBar` côté appelant).
    let sectionsCoordinateSpace: String
    var isSelecting: Bool = false
    var selectedItemIds: Set<Int> = []
    var onToggleSelection: ((Item) -> Void)? = nil
    let onLoadMore: (Item) async -> Void
    /// Bordure/halo additionnel dessiné sur la pochette quand l'exemplaire n'est pas sélectionné
    /// (ex: le halo rose du disque mis en avant dans la Collection après un ajout). Mutuellement
    /// exclusif avec la bordure de sélection, qui reste gérée en interne.
    var borderOverlay: (Item) -> AnyView = { _ in AnyView(EmptyView()) }
    /// Badges superposés aux coins de la pochette, composés librement par l'appelant (plusieurs
    /// `.overlay(alignment:)` chaînés sur une vue qui occupe toute la cellule).
    var cornerBadges: (Item) -> AnyView = { _ in AnyView(EmptyView()) }
    var contextMenuContent: (Item) -> AnyView = { _ in AnyView(EmptyView()) }

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 6, pinnedViews: [.sectionHeaders]) {
                if isLoading {
                    Section {
                        ForEach(0..<16, id: \.self) { _ in
                            SkeletonBlock(cornerRadius: 6)
                                .aspectRatio(1, contentMode: .fit)
                        }
                    } header: {
                        SkeletonSectionHeaderRow()
                            .padding(.vertical, 2)
                            .padding(.horizontal, 2)
                            // Trame étendue au-delà des bords du contenu (plutôt qu'un remplissage
                            // exactement ajusté) pour qu'il y ait une vraie marge visuelle avant le
                            // bord de la grille, sans déplacer le texte lui-même.
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.libraryHeaderBackground(for: colorScheme))
                                    .padding(.horizontal, -8)
                            }
                    }
                } else {
                ForEach(sections, id: \.key) { section in
                    Section {
                        ForEach(section.items) { item in
                            mosaicCell(for: item)
                        }
                    } header: {
                        LibrarySectionHeader(
                            token: indexToken(section),
                            title: displayTitle(section),
                            count: section.items.count,
                            artists: headerArtists(section)
                        )
                        .id(section.key)
                        // Même hauteur totale que l'en-tête en mode Liste : celui-ci cumule son
                        // propre `.padding(.vertical, 2)` interne avec les 2pt du `.listRowInsets`
                        // de `LibrarySectionHeader` (soit ~4pt par bord) — on reproduit donc ici
                        // le même total (2 + 2) plutôt que les 6pt précédents.
                        .padding(.vertical, 2)
                        .padding(.horizontal, 2)
                        // Trame étendue au-delà des bords du contenu (plutôt qu'un remplissage
                        // exactement ajusté) pour qu'il y ait une vraie marge visuelle avant le
                        // bord de la grille, sans déplacer le texte lui-même.
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.libraryHeaderBackground(for: colorScheme))
                                .padding(.horizontal, -8)
                        }
                        .reportingSectionOffset(key: section.key, coordinateSpace: sectionsCoordinateSpace)
                    }
                }
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, hasVerticalIndexBar ? 30 : 12)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .coordinateSpace(name: sectionsCoordinateSpace)
    }

    // MARK: - Vignette d'une pochette dans la mosaïque

    private func mosaicCell(for item: Item) -> some View {
        let info = item.basicInformation
        let coverURL = info.coverImage ?? info.thumb
        let isSelected = selectedItemIds.contains(item.id)

        return ZStack {
            NavigationLink(value: SearchDestination.release(item.releaseId, coverURL: coverURL)) {
                AsyncCoverImage(url: coverURL, cornerRadius: 6, showsBorder: true, targetSize: 100)
                    .aspectRatio(1, contentMode: .fit)
                    .opacity(isSelecting ? (isSelected ? 1.0 : 0.45) : 1.0)
                    // Ombre de contact (très proche) puis ombre d'ambiance flottante (large et
                    // douce) ; toutes deux atténuées pendant la sélection multiple, comme
                    // l'opacité de la pochette.
                    .shadow(color: .black.opacity(isSelecting ? (isSelected ? 0.30 : 0.12) : 0.22), radius: 5, x: 0, y: 3)
                    .shadow(color: .black.opacity(isSelecting ? (isSelected ? 0.45 : 0.18) : 0.35), radius: 16, x: 0, y: 10)
                    // Micro-bordure pour l'épaisseur carton, remplacée par la bordure de
                    // sélection quand cet exemplaire est coché.
                    .overlay {
                        if isSelecting && isSelected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.spinlogPink, lineWidth: 3)
                        } else {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                            borderOverlay(item)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if isSelecting {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isSelected ? Color.spinlogPink : Color.white)
                                .background(
                                    Circle()
                                        .fill(isSelected ? Color.white : Color.black.opacity(0.45))
                                        .padding(2)
                                )
                                .padding(6)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .overlay {
                        if !isSelecting {
                            cornerBadges(item)
                        }
                    }
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!isSelecting)
            .accessibilityHidden(isSelecting)

            if isSelecting {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onToggleSelection?(item)
                    }
                    .librarySelectionAccessibility(info: info, isSelected: isSelected) {
                        onToggleSelection?(item)
                    }
            }
        }
        .accessibilityLabel("\(info.title), \(info.artistNames)")
        .id(item.id)
        .animation(.librarySelectionToggle, value: isSelected)
        .task {
            await onLoadMore(item)
        }
        .contextMenu(isSelecting ? nil : ContextMenu { contextMenuContent(item) })
    }
}
