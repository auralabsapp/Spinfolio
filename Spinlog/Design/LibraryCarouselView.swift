import SwiftUI

/// Formules de dimensionnement du Carrousel (Collection/Wantlist), partagées avec
/// `LibraryCarouselSkeletonContent` pour que la pochette du squelette ait exactement la même
/// taille que la vraie carte centrale, y compris sur iPad — avant cette extraction, le squelette
/// de chaque écran ne reprenait que la formule iPhone (ou carrément des valeurs figées côté
/// Wantlist), donnant une pochette visiblement plus petite que la vraie au chargement sur iPad.
enum LibraryCarouselMetrics {
    static func cardSize(containerSize: CGSize, isRegularDisplay: Bool) -> CGFloat {
        if isRegularDisplay {
            let availableWidth = containerSize.width
            let availableHeight = containerSize.height > 0 ? containerSize.height : 800
            // Réserve ~260pt pour les métadonnées, boutons, scrubber et marges
            let heightCap = max(availableHeight - 260, 340)
            let widthCap = availableWidth * 0.70
            return min(widthCap, heightCap, 540)
        } else {
            return min(max(containerSize.width * 0.72, 230), 290)
        }
    }
}

/// Gabarit neutre affiché pendant le chargement du Carrousel (Collection/Wantlist), à la place
/// d'une icône de chargement : reproduit la structure réelle (pochette centrée avec ses voisines
/// qui dépassent, titre/artiste/année-format, puis des boutons d'action ronds) avec des blocs
/// animés (voir `SkeletonBlock`), pour que l'apparition du contenu réel ne fasse pas sauter la
/// page. `actionButtonCount` est le seul paramètre qui diffère réellement entre les deux écrans
/// (3 actions pour la Collection, 1 pour la Wantlist) — tout le reste est partagé à l'identique.
struct LibraryCarouselSkeletonContent: View {
    let containerSize: CGSize
    var actionButtonCount: Int

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularDisplay: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular
    }

    var body: some View {
        let coverSize = LibraryCarouselMetrics.cardSize(containerSize: containerSize, isRegularDisplay: isRegularDisplay)
        let sideSize = coverSize * 0.39

        VStack(spacing: 20) {
            Spacer(minLength: 0)

            // Cette rangée (voisine + pochette + voisine) est volontairement plus large que
            // l'écran — elle imite les voisines qui dépassent dans le vrai carrousel. Sans ce
            // `.frame(width:)` explicite, un `HStack` plus large que son contenant, placé dans un
            // `ScrollView` vertical (qui ne peut pas défiler horizontalement pour le recentrer),
            // s'ancre au bord de tête plutôt que d'être centré : tout le squelette (y compris le
            // texte en dessous, pourtant moins large que l'écran) se retrouvait alors décalé vers
            // la droite au lieu d'être centré.
            HStack(spacing: 16) {
                SkeletonBlock(cornerRadius: 10, width: sideSize, height: sideSize)
                SkeletonBlock(cornerRadius: 14, width: coverSize, height: coverSize)
                SkeletonBlock(cornerRadius: 10, width: sideSize, height: sideSize)
            }
            .frame(width: containerSize.width > 0 ? containerSize.width : nil)

            VStack(spacing: 6) {
                SkeletonBlock(width: coverSize * 0.7, height: 22)
                SkeletonBlock(width: coverSize * 0.5, height: 20)
                SkeletonBlock(cornerRadius: 10, width: coverSize * 0.4, height: 22)
                    .padding(.top, 2)
            }

            HStack(spacing: 12) {
                ForEach(0..<actionButtonCount, id: \.self) { _ in
                    SkeletonBlock(cornerRadius: 19, width: 38, height: 38)
                }
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Vue Carrousel générique, partagée par la Collection et la Wantlist (via `SortableLibraryItem`) :
/// défilement horizontal fluide de grandes pochettes vinyle avec disque sortant, effet de
/// transition 3D cover flow, informations de base et navigation rapide. Les deux écrans
/// partageaient ~300 lignes identiques (dimensionnement, défilement, mise en page de la carte) ;
/// seuls le badge secondaire (exemplaires/note pour la Collection, alerte de prix pour la
/// Wantlist) et les actions rapides diffèrent réellement — d'où les closures `secondaryBadge`/
/// `quickActions`, qui renvoient `AnyView` (même choix que `LibraryMosaicView`/`LibraryListView`).
struct LibraryCarouselView<Item: SortableLibraryItem>: View {
    let sections: [(key: String, items: [Item])]
    let indexEntries: [(token: String, sectionKey: String)]
    /// Jeton d'une section donnée — même closure que `LibraryListView`/`LibraryMosaicView`.
    /// Nécessaire pour `currentToken` : `indexEntries` ne garde qu'UNE section représentative par
    /// jeton (la première rencontrée, ex: un seul artiste par lettre) — y chercher la section
    /// courante par sa clé échoue dès qu'on navigue vers une autre section partageant ce même
    /// jeton, faisant disparaître le curseur de la barre de navigation horizontale.
    let indexToken: ((key: String, items: [Item])) -> String
    var isSelecting: Bool = false
    var selectedItemIds: Set<Int> = []
    var onToggleSelection: ((Item) -> Void)? = nil
    let onLoadMore: (Item) async -> Void
    /// Déclenche un saut animé vers un élément précis (ex: "Disque au hasard" en Collection) —
    /// `nil` tant qu'aucun appelant n'a ce besoin (la Wantlist n'en a pas aujourd'hui).
    var scrollToTrigger: ScrollTargetTrigger? = nil
    /// Ligne de badge sous la pastille année/format, responsable de son propre espacement
    /// (`.padding(.top, 2)`) puisqu'elle peut être vide (ex: aucune alerte wantlist définie).
    var secondaryBadge: (Item) -> AnyView = { _ in AnyView(EmptyView()) }
    /// Contenu des actions rapides sous les infos (masquées en mode sélection, transition et
    /// espacement gérés ici, communs aux deux écrans).
    var quickActions: (Item) -> AnyView = { _ in AnyView(EmptyView()) }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // `ScrollPosition` (et non `scrollPosition(id:)`) : en plus de suivre l'identité de la carte
    // centrée au fil du défilement normal, elle permet de sauter à un décalage (`x:`) calculé
    // analytiquement — voir `animatedScroll` pour la raison de ce choix.
    @State private var scrollPosition = ScrollPosition(idType: Int.self)
    @State private var displayItemId: Int?
    @State private var hasSetInitialPosition = false
    // Pas de valeur par défaut devinée (ex: 390x600) : tant que la vraie taille n'a pas été
    // mesurée par le `GeometryReader` ci-dessous, `trySetInitialPosition()` ne fixe pas encore
    // `scrollPosition`. Deviner une taille puis la corriger après coup laissait le `ScrollPosition`
    // déjà établi sur un padding/largeur de carte erronés — le `ScrollView` ne recentre que
    // lorsque l'id/décalage cible change, pas quand seule la géométrie change — d'où un espacement
    // figé et faux entre les pochettes jusqu'à un changement de mode d'affichage (qui recrée la vue).
    @State private var containerSize: CGSize = .zero

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var isRegularDisplay: Bool {
        isPad || horizontalSizeClass == .regular
    }

    private var cardSize: CGFloat {
        LibraryCarouselMetrics.cardSize(containerSize: containerSize, isRegularDisplay: isRegularDisplay)
    }

    private var cardWidth: CGFloat {
        cardSize
    }

    private var horizontalPadding: CGFloat {
        max((containerSize.width - cardSize) / 2, 0)
    }

    private var cardSpacing: CGFloat {
        if isRegularDisplay {
            // Sur iPad : espacement égal au padding horizontal + marge pour repousser
            // la jaquette adjacente exactement hors de l'écran. Résultat : UNE SEULE jaquette est visible au repos.
            return max(horizontalPadding + 20, 60)
        } else {
            return 28
        }
    }

    private var items: [Item] {
        sections.flatMap { $0.items }
    }

    private var currentSectionKey: String? {
        guard let displayItemId else { return sections.first?.key }
        return sections.first(where: { section in
            section.items.contains(where: { $0.id == displayItemId })
        })?.key
    }

    private var currentToken: String? {
        guard let currentSectionKey,
              let section = sections.first(where: { $0.key == currentSectionKey }) else { return nil }
        return indexToken(section)
    }

    var body: some View {
        // Aplati UNE fois par passage de rendu plutôt qu'à chaque accès à `items` (jusqu'à 4-5
        // fois par rendu : `ForEach`, et `positionIndicator` + son propre `firstIndex(where:)`
        // une fois par carte matérialisée) — `items` reste une propriété calculée pour les appels
        // peu fréquents (saut programmé, position initiale), qui n'ont pas besoin de ce cache.
        let currentItems = items
        VStack(spacing: isRegularDisplay ? 6 : 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: cardSpacing) {
                    ForEach(currentItems) { item in
                        let isRegularDisplay = isRegularDisplay
                        carouselCard(for: item, size: cardSize, cardWidth: cardWidth, items: currentItems)
                            .id(item.id)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1.0 : (isRegularDisplay ? 0.92 : 0.88))
                                    .opacity(phase.isIdentity ? 1.0 : (isRegularDisplay ? 0.0 : 0.70))
                            }
                            .task {
                                await onLoadMore(item)
                            }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, horizontalPadding)
                .padding(.top, isRegularDisplay ? 16 : 10)
                .padding(.bottom, 2)
            }
            // `limitBehavior: .never` : par défaut, `.viewAligned` limite le nombre de pochettes
            // qu'un seul défilement peut traverser en largeur compacte (donc sur iPhone, voir la
            // doc de `ViewAlignedScrollTargetBehavior`). Sans ce réglage, un tirage au sort lointain
            // (bouton « Disque au hasard ») voyait son animation s'arrêter avant d'être centrée sur
            // la bonne pochette, puisque la limite plafonnait le défilement avant la cible demandée.
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
            .scrollPosition($scrollPosition, anchor: .center)

            // Barre de navigation rapide inférieure (Scrubber horizontal A-Z / Années)
            if indexEntries.count > 1 {
                HorizontalSectionIndexBar(
                    entries: indexEntries,
                    currentToken: currentToken
                ) { sectionKey in
                    if let firstItem = sections.first(where: { $0.key == sectionKey })?.items.first {
                        animatedScroll(to: firstItem.id, isRandom: false)
                    }
                }
                .padding(.horizontal, isRegularDisplay ? 40 : 20)
            }
        }
        // La hauteur n'est plus forcée à `.infinity` ici : le parent (`CollectionView`/
        // `WantlistView`) place déjà ce contenu dans un `ScrollView` vertical avec un
        // `.frame(minHeight:)` mesuré par un `GeometryReader` externe, pour fournir une hauteur
        // disponible réaliste au calcul de `cardSize` sur iPad sans pousser le `ScrollView` à
        // proposer une hauteur infinie.
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: LibraryCarouselContainerSizeKey.self, value: geo.size)
            }
        )
        .onPreferenceChange(LibraryCarouselContainerSizeKey.self) { newSize in
            if newSize.width > 0 && newSize != containerSize {
                containerSize = newSize
            }
            trySetInitialPosition()
        }
        .onAppear {
            trySetInitialPosition()
        }
        .onChange(of: items.first?.id) { _, _ in
            trySetInitialPosition()
        }
        .onChange(of: scrollPosition) { _, newValue in
            if let newId = newValue.viewID(type: Int.self) {
                displayItemId = newId
            }
        }
        .onChange(of: scrollToTrigger) { _, newTrigger in
            guard let newTrigger else { return }
            animatedScroll(to: newTrigger.id, isRandom: true)
        }
    }

    /// Fixe la position de défilement initiale (1er album) une seule fois, et seulement après
    /// avoir mesuré la vraie largeur du conteneur — voir le commentaire sur `containerSize`.
    private func trySetInitialPosition() {
        guard !hasSetInitialPosition, containerSize.width > 0, let first = items.first else { return }
        hasSetInitialPosition = true
        scrollPosition.scrollTo(id: first.id)
        displayItemId = first.id
    }

    /// Fait défiler vers l'album ciblé (tiré au sort, ou choisi via la barre de navigation rapide).
    ///
    /// On calcule le décalage cible analytiquement plutôt que de sauter par identité
    /// (`scrollTo(id:)`) : toutes les cartes du carrousel ont exactement la même largeur et le
    /// même espacement (`cardWidth`/`cardSpacing`), donc la position de n'importe quel index se
    /// déduit sans dépendre de la matérialisation réelle de sa carte dans le `LazyHStack`. Un saut
    /// par identité vers une cible encore jamais affichée dépend de cette matérialisation pour
    /// connaître sa géométrie exacte : selon son état d'avancement au moment du calcul, l'animation
    /// pouvait s'arrêter avant d'être centrée, ou être systématiquement décalée. Le calcul direct
    /// n'a pas ce problème : il donne le même résultat pour une carte voisine ou à l'autre bout de
    /// la collection. (`horizontalPadding` ajoute une marge symétrique de part et d'autre du
    /// contenu, exactement égale à la moitié de l'espace libre, donc elle s'annule avec la moitié de
    /// la largeur du conteneur dans ce calcul — voir le détail dans l'historique de ce fichier.)
    private func animatedScroll(to targetId: Int, isRandom: Bool) {
        guard let targetIndex = items.firstIndex(where: { $0.id == targetId }) else { return }

        if isRandom {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        displayItemId = targetId
        let targetOffsetX = CGFloat(targetIndex) * (cardWidth + cardSpacing)

        withAnimation(.scrollToItem) {
            scrollPosition.scrollTo(x: targetOffsetX)
        }
    }

    // MARK: - Carte Carrousel

    private func carouselCard(for item: Item, size: CGFloat, cardWidth: CGFloat, items: [Item]) -> some View {
        let info = item.basicInformation
        let coverURL = info.coverImage ?? info.thumb
        let isSelected = selectedItemIds.contains(item.id)

        return VStack(spacing: isRegularDisplay ? 16 : 14) {
            // Pochette d'album sans disque vinyle sortant, parfaitement centrée
            ZStack {
                NavigationLink(value: SearchDestination.release(item.releaseId, coverURL: coverURL)) {
                    AsyncCoverImage(url: coverURL, cornerRadius: isRegularDisplay ? 18 : 14, targetSize: size)
                        .frame(width: size, height: size)
                        .opacity(isSelecting ? (isSelected ? 1.0 : 0.45) : 1.0)
                        // Ombre de contact (très proche) puis ombre d'ambiance flottante (large et
                        // douce) ; toutes deux atténuées pendant la sélection multiple, comme
                        // l'opacité de la pochette.
                        .shadow(color: .black.opacity(isSelecting ? (isSelected ? 0.30 : 0.12) : 0.22), radius: isRegularDisplay ? 7 : 5, x: 0, y: isRegularDisplay ? 4 : 3)
                        .shadow(color: .black.opacity(isSelecting ? (isSelected ? 0.45 : 0.18) : 0.35), radius: isRegularDisplay ? 26 : 18, x: 0, y: isRegularDisplay ? 14 : 11)
                        .overlay(
                            RoundedRectangle(cornerRadius: isRegularDisplay ? 18 : 14, style: .continuous)
                                .strokeBorder(
                                    isSelecting && isSelected
                                        ? Color.spinlogPink
                                        : Color.white.opacity(0.12),
                                    lineWidth: isSelecting && isSelected ? 3.5 : 1
                                )
                        )
                        .overlay(alignment: .topTrailing) {
                            if isSelecting {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(isRegularDisplay ? .title : .title2)
                                    .foregroundStyle(isSelected ? Color.spinlogPink : Color.white)
                                    .background(
                                        Circle()
                                            .fill(isSelected ? Color.white : Color.black.opacity(0.5))
                                            .padding(2)
                                    )
                                    .padding(isRegularDisplay ? 16 : 12)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
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
                        .librarySelectionAccessibility(info: info, isSelected: isSelected) {
                            onToggleSelection?(item)
                        }
                }
            }

            // Informations textuelles
            VStack(spacing: isRegularDisplay ? 6 : 4) {
                Text(info.title)
                    .font(isRegularDisplay ? .title2.weight(.bold) : .headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: isRegularDisplay ? cardWidth * 1.15 : cardWidth)

                // Chaque nom ouvre la fiche de l'artiste ; en mode sélection, le toucher
                // revient au bloc de texte (sélection du disque).
                ArtistNameLinks(artists: info.artists ?? [], fallback: info.artistNames)
                    .font(isRegularDisplay ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(Color.spinlogPink)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .frame(maxWidth: isRegularDisplay ? cardWidth * 1.15 : cardWidth)
                    .allowsHitTesting(!isSelecting)

                // Année & Format
                HStack(spacing: 6) {
                    if let year = info.year, year > 0 {
                        Text(String(year))
                            .font(isRegularDisplay ? .footnote.bold() : .caption2.bold())
                    }

                    if let formats = info.formats, !formats.isEmpty {
                        if let year = info.year, year > 0 {
                            Text("•").font(isRegularDisplay ? .footnote : .caption2).foregroundStyle(.tertiary)
                        }
                        Text(formats.compactMap(\.name).joined(separator: ", "))
                            .font(isRegularDisplay ? .footnote : .caption2)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(Color.appSecondaryText)
                .padding(.horizontal, isRegularDisplay ? 14 : 10)
                .padding(.vertical, isRegularDisplay ? 4 : 3)
                .background(Color.primary.opacity(0.05), in: Capsule())
                .padding(.top, 2)

                secondaryBadge(item)
            }
            .padding(.top, isRegularDisplay ? 8 : 6)
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelecting {
                    onToggleSelection?(item)
                }
            }

            // Actions rapides (masquées en mode sélection)
            if !isSelecting {
                quickActions(item)
                    .padding(.top, isRegularDisplay ? 8 : 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))

                // Indicateur de position (ex : "14 sur 85"), juste sous les icônes d'actions.
                positionIndicator(items: items)
                    .padding(.top, isRegularDisplay ? 8 : 4)
            }
        }
        .frame(width: cardWidth)
        .animation(.librarySelectionToggle, value: isSelected)
    }

    // MARK: - Indicateur de position

    private func positionIndicator(items: [Item]) -> some View {
        let currentIndex = items.firstIndex(where: { $0.id == displayItemId }) ?? 0
        return HStack(spacing: 6) {
            Image(systemName: "opticaldisc")
                .font(isRegularDisplay ? .footnote : .caption2)
                .foregroundStyle(Color.spinlogPink)
            Text("\(currentIndex + 1) sur \(items.count)")
                .font(isRegularDisplay ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, isRegularDisplay ? 18 : 14)
        .padding(.vertical, isRegularDisplay ? 8 : 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}


private struct LibraryCarouselContainerSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
