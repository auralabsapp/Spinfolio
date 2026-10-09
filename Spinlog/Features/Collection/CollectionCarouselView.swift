import SwiftUI
import Kingfisher

/// Vue Carrousel pour la Collection : défilement horizontal fluide de grandes pochettes vinyle
/// avec disque sortant, effet de transition 3D cover flow, informations de base et actions rapides.
struct CollectionCarouselView: View {
    let sections: [(key: String, items: [CollectionItem])]
    let indexEntries: [(token: String, sectionKey: String)]
    let copyBadge: (CollectionItem) -> String?
    let isPlaying: (Int) -> Bool
    var isSelecting: Bool = false
    var selectedItemIds: Set<Int> = []
    var onToggleSelection: ((CollectionItem) -> Void)? = nil
    let onTriggerListening: (CollectionItem) -> Void
    let onStopListening: (CollectionItem) -> Void
    let onShelfPlacement: (CollectionItem) -> Void
    let onEditItem: (CollectionItem) -> Void
    let onLoadMore: (CollectionItem) async -> Void
    var scrollToTrigger: ScrollTargetTrigger? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var currentItemId: Int?
    @State private var displayItemId: Int?
    @State private var randomScrollTask: Task<Void, Never>?
    // Pas de valeur par défaut devinée (ex: 390x600) : tant que la vraie taille n'a pas été
    // mesurée par le `GeometryReader` ci-dessous, `trySetInitialPosition()` ne fixe pas encore
    // `currentItemId`. Deviner une taille puis la corriger après coup laissait le `ScrollPosition`
    // déjà établi sur un padding/largeur de carte erronés — `scrollPosition(id:)` ne recentre que
    // lorsque l'id change, pas quand seule la géométrie change — d'où un espacement figé et faux
    // entre les pochettes jusqu'à un changement de mode d'affichage (qui recrée toute la vue).
    @State private var containerSize: CGSize = .zero

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var isRegularDisplay: Bool {
        isPad || horizontalSizeClass == .regular
    }

    private var cardSize: CGFloat {
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

    private var items: [CollectionItem] {
        sections.flatMap { $0.items }
    }

    private var currentSectionKey: String? {
        guard let displayItemId else { return sections.first?.key }
        return sections.first(where: { section in
            section.items.contains(where: { $0.id == displayItemId })
        })?.key
    }

    private var currentToken: String? {
        guard let currentSectionKey else { return nil }
        return indexEntries.first(where: { $0.sectionKey == currentSectionKey })?.token
    }

    var body: some View {
        VStack(spacing: isRegularDisplay ? 18 : 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: cardSpacing) {
                    ForEach(items) { item in
                        let isRegularDisplay = isRegularDisplay
                        carouselCard(for: item, size: cardSize, cardWidth: cardWidth)
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
                .padding(.bottom, 6)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentItemId, anchor: .center)

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

            // Indicateur de position (ex : "14 sur 85")
            if !items.isEmpty {
                positionIndicator
            }
        }
        // La hauteur n'est plus forcée à `.infinity` ici : le parent (`CollectionView`) place
        // déjà ce contenu dans un `ScrollView` vertical avec un `.frame(minHeight:)` mesuré par un
        // `GeometryReader` externe, pour fournir une hauteur disponible réaliste au calcul de
        // `cardSize` sur iPad sans pousser le `ScrollView` à proposer une hauteur infinie.
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: CarouselContainerSizeKey.self, value: geo.size)
            }
        )
        .onPreferenceChange(CarouselContainerSizeKey.self) { newSize in
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
        .onChange(of: currentItemId) { _, newValue in
            if let newValue {
                displayItemId = newValue
            }
        }
        .onChange(of: scrollToTrigger) { _, newTrigger in
            guard let newTrigger else { return }
            animatedScroll(to: newTrigger.id, isRandom: true)
        }
        .onDisappear {
            randomScrollTask?.cancel()
        }
    }

    /// Fixe la position de défilement initiale (1er album) une seule fois, et seulement après
    /// avoir mesuré la vraie largeur du conteneur — voir le commentaire sur `containerSize`.
    private func trySetInitialPosition() {
        guard currentItemId == nil, containerSize.width > 0, let first = items.first else { return }
        currentItemId = first.id
        displayItemId = first.id
    }

    /// Fait défiler directement vers l'album tiré au sort en un mouvement continu, fluide et naturel.
    private func animatedScroll(to targetId: Int, isRandom: Bool) {
        randomScrollTask?.cancel()

        if isRandom {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        withAnimation(.spring(response: 0.58, dampingFraction: 0.86)) {
            currentItemId = targetId
            displayItemId = targetId
        }
    }

    // MARK: - Carte Carrousel

    private func carouselCard(for item: CollectionItem, size: CGFloat, cardWidth: CGFloat) -> some View {
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
                        .shadow(color: .black.opacity(isSelected ? 0.45 : 0.28), radius: isRegularDisplay ? 20 : 14, x: 0, y: isRegularDisplay ? 10 : 8)
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
                .allowsHitTesting(!isSelecting)

                if isSelecting {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
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

                Text(info.artistNames)
                    .font(isRegularDisplay ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(Color.spinlogPink)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .frame(maxWidth: isRegularDisplay ? cardWidth * 1.15 : cardWidth)

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

                // Badge d'exemplaire et note
                HStack(spacing: 8) {
                    if let badge = copyBadge(item) {
                        Text(badge)
                            .font(isRegularDisplay ? .footnote.bold() : .caption2.bold())
                            .padding(.horizontal, isRegularDisplay ? 9 : 7)
                            .padding(.vertical, isRegularDisplay ? 3 : 2)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }

                    if item.rating > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: isRegularDisplay ? 11 : 9))
                                .foregroundStyle(Color.orange)
                            Text("\(item.rating)")
                                .font(isRegularDisplay ? .footnote.bold() : .caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 2)
            }
            .padding(.top, isRegularDisplay ? 8 : 6)
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelecting {
                    onToggleSelection?(item)
                }
            }

            // Boutons d'action rapide (masqués en mode sélection)
            if !isSelecting {
                HStack(spacing: isRegularDisplay ? 16 : 12) {
                    // Écoute en direct (Start / Stop)
                    Button {
                        if isPlaying(item.releaseId) {
                            onStopListening(item)
                        } else {
                            onTriggerListening(item)
                        }
                    } label: {
                        Image(systemName: isPlaying(item.releaseId) ? "stop.fill" : "opticaldisc.fill")
                            .font(.system(size: isRegularDisplay ? 17 : 14, weight: .bold))
                            .foregroundStyle(isPlaying(item.releaseId) ? .white : Color.spinlogPink)
                            .frame(width: isRegularDisplay ? 46 : 38, height: isRegularDisplay ? 46 : 38)
                            .background(
                                isPlaying(item.releaseId) ? Color(uiColor: .systemGray) : Color.spinlogPinkBadge,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPlaying(item.releaseId) ? Text("Arrêter l'écoute") : Text("J'écoute ce disque sur la platine"))

                    // Où ranger
                    Button {
                        onShelfPlacement(item)
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
                        onEditItem(item)
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
                .padding(.top, isRegularDisplay ? 8 : 4)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .frame(width: cardWidth)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isSelected)
    }

    // MARK: - Indicateur de position

    private var positionIndicator: some View {
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

private struct CarouselContainerSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
