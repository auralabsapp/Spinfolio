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
    @State private var currentItemId: Int?
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
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                proxy.scrollTo(firstItem.id, anchor: .center)
                            }
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
                        .preference(key: WantlistCarouselWidthPreferenceKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(WantlistCarouselWidthPreferenceKey.self) { newWidth in
                if newWidth > 0 && newWidth != containerWidth {
                    containerWidth = newWidth
                }
            }
            .onAppear {
                if currentItemId == nil, let first = items.first {
                    currentItemId = first.id
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

        return VStack(spacing: 14) {
            // Pochette d'album sans disque vinyle sortant, parfaitement centrée
            ZStack {
                NavigationLink(value: SearchDestination.release(item.id, coverURL: coverURL)) {
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

                // Badge d'alerte prix si configurée (hors sélection)
                if !isSelecting, let alert {
                    HStack(spacing: 4) {
                        Image(systemName: alert.isTriggered ? "bell.badge.fill" : "bell.fill")
                            .font(.system(size: 10))
                        Text("≤ \(alert.targetPrice.formatted(.currency(code: alert.currency)))")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(alert.isTriggered ? .green : Color.spinlogPink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        alert.isTriggered ? Color.green.opacity(0.12) : Color.spinlogPinkBadge,
                        in: Capsule()
                    )
                    .padding(.top, 2)
                }
            }
            .padding(.top, 6)
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
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(alert != nil ? (alert?.isTriggered == true ? .green : Color.spinlogPink) : Color.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        alert != nil ? (alert?.isTriggered == true ? Color.green.opacity(0.12) : Color.spinlogPinkBadge) : Color.primary.opacity(0.06),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
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

private struct WantlistCarouselWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}
