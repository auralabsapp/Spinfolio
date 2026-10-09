import SwiftUI

/// Vue Mosaïque pour la Collection : grille de pochettes vinyles carrées sur 3 colonnes,
/// avec en-têtes de sections épinglés (pinned section headers), badges d'écoute/exemplaires/notes,
/// menu contextuel d'actions rapides et compatibilité totale avec la barre verticale de navigation A-Z.
struct CollectionMosaicView: View {
    let sections: [(key: String, items: [CollectionItem])]
    let indexToken: ((key: String, items: [CollectionItem])) -> String
    let displayTitle: ((key: String, items: [CollectionItem])) -> String
    let copyBadge: (CollectionItem) -> String?
    let isPlaying: (Int) -> Bool
    let highlightedItemId: Int?
    let hasVerticalIndexBar: Bool
    var isSelecting: Bool = false
    var selectedItemIds: Set<Int> = []
    var onToggleSelection: ((CollectionItem) -> Void)? = nil
    let onTriggerListening: (CollectionItem) -> Void
    let onStopListening: (CollectionItem) -> Void
    let onShelfPlacement: (CollectionItem) -> Void
    let onEditItem: (CollectionItem) -> Void
    let onDeleteItem: (CollectionItem) -> Void
    let onLoadMore: (CollectionItem) async -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 6, pinnedViews: [.sectionHeaders]) {
                ForEach(sections, id: \.key) { section in
                    Section {
                        ForEach(section.items) { item in
                            mosaicCell(for: item)
                        }
                    } header: {
                        LibrarySectionHeader(
                            token: indexToken(section),
                            title: displayTitle(section),
                            count: section.items.count
                        )
                        .id(section.key)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 2)
                        .background(.regularMaterial)
                    }
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, hasVerticalIndexBar ? 26 : 12)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Vignette d'une pochette dans la mosaïque

    private func mosaicCell(for item: CollectionItem) -> some View {
        let info = item.basicInformation
        let coverURL = info.coverImage ?? info.thumb
        let isSelected = selectedItemIds.contains(item.id)

        return ZStack {
            NavigationLink(value: SearchDestination.release(item.releaseId, coverURL: coverURL)) {
                AsyncCoverImage(url: coverURL, cornerRadius: 6, showsBorder: true, targetSize: 130)
                    .aspectRatio(1, contentMode: .fit)
                    .opacity(isSelecting ? (isSelected ? 1.0 : 0.45) : 1.0)
                    .overlay {
                        if highlightedItemId == item.id {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.spinlogPink, lineWidth: 3)
                                .shadow(color: Color.spinlogPink.opacity(0.6), radius: 6)
                        } else if isSelecting && isSelected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.spinlogPink, lineWidth: 3)
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
                    .overlay(alignment: .topTrailing) {
                        if !isSelecting, let badge = copyBadge(item) {
                            Text(badge)
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.7), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
                                .padding(4)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if !isSelecting && isPlaying(item.releaseId) {
                            HStack(spacing: 3) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 8, weight: .bold))
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
                        if !isSelecting && item.rating > 0 {
                            HStack(spacing: 1.5) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 7))
                                    .foregroundStyle(Color.orange)
                                Text("\(item.rating)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.65), in: Capsule())
                            .padding(4)
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
        .accessibilityLabel("\(info.title), \(info.artistNames)")
        .id(item.id)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isSelected)
        .task {
            await onLoadMore(item)
        }
        .contextMenu(isSelecting ? nil : ContextMenu {
            if isPlaying(item.releaseId) {
                Button {
                    onStopListening(item)
                } label: {
                    Label("Arrêter l'écoute", systemImage: "stop.fill")
                }
            } else {
                Button {
                    onTriggerListening(item)
                } label: {
                    Label("J'écoute ce disque sur la platine", systemImage: "opticaldisc.fill")
                }
            }

            Button {
                onShelfPlacement(item)
            } label: {
                Label("Où ranger", systemImage: "books.vertical.fill")
            }

            Button {
                onEditItem(item)
            } label: {
                Label("Modifier la note / notes", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDeleteItem(item)
            } label: {
                Label("Supprimer de la collection", systemImage: "trash")
            }
        })
    }
}
