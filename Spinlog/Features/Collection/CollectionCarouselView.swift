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

    @State private var currentItemId: Int?
    @State private var displayItemId: Int?
    @State private var randomScrollTask: Task<Void, Never>?
    @State private var containerWidth: CGFloat = 390

    private var cardSize: CGFloat {
        min(max(containerWidth * 0.72, 230), 290)
    }

    private var cardWidth: CGFloat {
        cardSize
    }

    private var horizontalPadding: CGFloat {
        max((containerWidth - cardSize) / 2, 0)
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
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 28) {
                    ForEach(items) { item in
                        carouselCard(for: item, size: cardSize, cardWidth: cardWidth)
                            .id(item.id)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1.0 : 0.88)
                                    .opacity(phase.isIdentity ? 1.0 : 0.70)
                            }
                            .task {
                                await onLoadMore(item)
                            }
                    }
                }
                .scrollTargetLayout()
                .padding(.top, 10)
                .padding(.bottom, 6)
            }
            .contentMargins(.horizontal, horizontalPadding, for: .scrollContent)
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
                .padding(.horizontal, 20)
            }

            // Indicateur de position (ex : "14 sur 85")
            if !items.isEmpty {
                positionIndicator
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: CarouselWidthPreferenceKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(CarouselWidthPreferenceKey.self) { newWidth in
            if newWidth > 0 && newWidth != containerWidth {
                containerWidth = newWidth
            }
        }
        .onAppear {
            if currentItemId == nil, let first = items.first {
                currentItemId = first.id
                displayItemId = first.id
            }
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

        return VStack(spacing: 14) {
            // Pochette d'album sans disque vinyle sortant, parfaitement centrée
            ZStack {
                NavigationLink(value: SearchDestination.release(item.releaseId, coverURL: coverURL)) {
                    AsyncCoverImage(url: coverURL, cornerRadius: 14, targetSize: size)
                        .frame(width: size, height: size)
                        .opacity(isSelecting ? (isSelected ? 1.0 : 0.45) : 1.0)
                        .shadow(color: .black.opacity(isSelected ? 0.42 : 0.25), radius: 14, x: 0, y: 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                                    .font(.title2)
                                    .foregroundStyle(isSelected ? Color.spinlogPink : Color.white)
                                    .background(
                                        Circle()
                                            .fill(isSelected ? Color.white : Color.black.opacity(0.5))
                                            .padding(2)
                                    )
                                    .padding(12)
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
            VStack(spacing: 4) {
                Text(info.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: cardWidth)

                Text(info.artistNames)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.spinlogPink)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .frame(maxWidth: cardWidth)

                // Année & Format
                HStack(spacing: 6) {
                    if let year = info.year, year > 0 {
                        Text(String(year))
                            .font(.caption2.bold())
                    }

                    if let formats = info.formats, !formats.isEmpty {
                        if let year = info.year, year > 0 {
                            Text("•").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text(formats.compactMap(\.name).joined(separator: ", "))
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(Color.appSecondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05), in: Capsule())
                .padding(.top, 2)

                // Badge d'exemplaire et note
                HStack(spacing: 8) {
                    if let badge = copyBadge(item) {
                        Text(badge)
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }

                    if item.rating > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.orange)
                            Text("\(item.rating)")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 2)
            }
            .padding(.top, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelecting {
                    onToggleSelection?(item)
                }
            }

            // Boutons d'action rapide (masqués en mode sélection)
            if !isSelecting {
                HStack(spacing: 12) {
                    // Écoute en direct (Start / Stop)
                    Button {
                        if isPlaying(item.releaseId) {
                            onStopListening(item)
                        } else {
                            onTriggerListening(item)
                        }
                    } label: {
                        Image(systemName: isPlaying(item.releaseId) ? "stop.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isPlaying(item.releaseId) ? .white : Color.spinlogPink)
                            .frame(width: 38, height: 38)
                            .background(
                                isPlaying(item.releaseId) ? Color(uiColor: .systemGray) : Color.spinlogPinkBadge,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPlaying(item.releaseId) ? "Arrêter l'écoute" : "Écouter ce disque")

                    // Où ranger
                    Button {
                        onShelfPlacement(item)
                    } label: {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.indigo)
                            .frame(width: 38, height: 38)
                            .background(Color.indigo.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Où ranger ce disque")

                    // Modifier notes/note
                    Button {
                        onEditItem(item)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.appSecondaryText)
                            .frame(width: 38, height: 38)
                            .background(Color.primary.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Modifier la note et les commentaires")
                }
                .padding(.top, 4)
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
                .font(.caption2)
                .foregroundStyle(Color.spinlogPink)
            Text("\(currentIndex + 1) sur \(items.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct CarouselWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}
