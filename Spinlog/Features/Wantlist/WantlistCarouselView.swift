import SwiftUI
import Kingfisher

/// Vue Carrousel pour la Wantlist : défilement horizontal fluide de grandes pochettes vinyle
/// avec disque sortant, effet de transition 3D cover flow, alertes prix et actions rapides.
struct WantlistCarouselView: View {
    let sections: [(key: String, items: [WantlistItem])]
    let indexEntries: [(token: String, sectionKey: String)]
    var isSelecting: Bool = false
    var selectedItemIds: Set<Int> = []
    var onToggleSelection: ((WantlistItem) -> Void)? = nil
    let onAlertTap: (WantlistItem) -> Void
    let onLoadMore: (WantlistItem) async -> Void

    private var alertStore = WantlistAlertStore.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var currentItemId: Int?
    @State private var containerSize: CGSize = CGSize(width: 390, height: 600)

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

    private var items: [WantlistItem] {
        sections.flatMap { $0.items }
    }

    private var currentSectionKey: String? {
        guard let currentItemId else { return sections.first?.key }
        return sections.first(where: { section in
            section.items.contains(where: { $0.id == currentItemId })
        })?.key
    }

    private var currentToken: String? {
        guard let currentSectionKey else { return nil }
        return indexEntries.first(where: { $0.sectionKey == currentSectionKey })?.token
    }

    var body: some View {
        ScrollViewReader { proxy in
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
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                proxy.scrollTo(firstItem.id, anchor: .center)
                            }
                        }
                    }
                    .padding(.horizontal, isRegularDisplay ? 40 : 20)
                }

                // Indicateur de position (ex : "14 sur 85")
                if !items.isEmpty {
                    positionIndicator
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: WantlistCarouselContainerSizeKey.self, value: geo.size)
                }
            )
            .onPreferenceChange(WantlistCarouselContainerSizeKey.self) { newSize in
                if newSize.width > 0 && newSize != containerSize {
                    containerSize = newSize
                }
            }
            .onAppear {
                if currentItemId == nil, let first = items.first {
                    currentItemId = first.id
                }
            }
            .onChange(of: items.first?.id) { _, firstId in
                if currentItemId == nil, let firstId {
                    currentItemId = firstId
                }
            }
        }
    }

    // MARK: - Carte Carrousel

    private func carouselCard(for item: WantlistItem, size: CGFloat, cardWidth: CGFloat) -> some View {
        let info = item.basicInformation
        let coverURL = info.coverImage ?? info.thumb
        let alert = alertStore.alert(for: item.id)
        let isSelected = selectedItemIds.contains(item.id)

        return VStack(spacing: isRegularDisplay ? 16 : 14) {
            // Pochette d'album sans disque vinyle sortant, parfaitement centrée
            ZStack {
                NavigationLink(value: SearchDestination.release(item.id, coverURL: coverURL)) {
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

                // Badge d'alerte prix si configurée (hors sélection)
                if !isSelecting, let alert {
                    HStack(spacing: 4) {
                        Image(systemName: alert.isTriggered ? "bell.badge.fill" : "bell.fill")
                            .font(.system(size: isRegularDisplay ? 12 : 10))
                        Text("≤ \(alert.targetPrice.formatted(.currency(code: alert.currency)))")
                            .font(isRegularDisplay ? .footnote.bold() : .caption2.bold())
                    }
                    .foregroundStyle(alert.isTriggered ? .green : Color.spinlogPink)
                    .padding(.horizontal, isRegularDisplay ? 10 : 8)
                    .padding(.vertical, isRegularDisplay ? 4 : 3)
                    .background(
                        alert.isTriggered ? Color.green.opacity(0.12) : Color.spinlogPinkBadge,
                        in: Capsule()
                    )
                    .padding(.top, 2)
                }
            }
            .padding(.top, isRegularDisplay ? 8 : 6)
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelecting {
                    onToggleSelection?(item)
                }
            }

            // Bouton pour configurer l'alerte prix (masqué en mode sélection)
            if !isSelecting {
                Button {
                    onAlertTap(item)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: alert != nil ? (alert?.isTriggered == true ? "bell.badge.fill" : "bell.fill") : "bell")
                        Text(alert != nil ? "Alerte active" : "Définir alerte prix")
                    }
                    .font(isRegularDisplay ? .subheadline.weight(.semibold) : .footnote.weight(.semibold))
                    .foregroundStyle(alert != nil ? (alert?.isTriggered == true ? .green : Color.spinlogPink) : Color.primary)
                    .padding(.horizontal, isRegularDisplay ? 18 : 14)
                    .padding(.vertical, isRegularDisplay ? 10 : 8)
                    .background(
                        alert != nil ? (alert?.isTriggered == true ? Color.green.opacity(0.12) : Color.spinlogPinkBadge) : Color.primary.opacity(0.06),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, isRegularDisplay ? 8 : 4)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .frame(width: cardWidth)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isSelected)
    }

    // MARK: - Indicateur de position

    private var positionIndicator: some View {
        let currentIndex = items.firstIndex(where: { $0.id == currentItemId }) ?? 0
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

private struct WantlistCarouselContainerSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
