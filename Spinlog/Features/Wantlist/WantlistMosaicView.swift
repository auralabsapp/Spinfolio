import SwiftUI

/// Vue Mosaïque pour la Wantlist : grille de pochettes vinyles carrées sur 3 colonnes,
/// avec en-têtes de sections épinglés, indicateur d'alerte de prix et navigation verticale A-Z.
struct WantlistMosaicView: View {
    let sections: [(key: String, items: [WantlistItem])]
    let indexToken: ((key: String, items: [WantlistItem])) -> String
    let displayTitle: ((key: String, items: [WantlistItem])) -> String
    let hasVerticalIndexBar: Bool
    var isSelecting: Bool = false
    var selectedItemIds: Set<Int> = []
    var onToggleSelection: ((WantlistItem) -> Void)? = nil
    let onAlertTap: (WantlistItem) -> Void
    let onLoadMore: (WantlistItem) async -> Void

    private var alertStore = WantlistAlertStore.shared

    private let columns = [
        GridItem(.flexible(), spacing: 6),
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
                        // Voir le même commentaire dans CollectionMosaicView : même hauteur
                        // totale que l'en-tête en mode Liste.
                        .padding(.vertical, 2)
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

    private func mosaicCell(for item: WantlistItem) -> some View {
        let info = item.basicInformation
        let coverURL = info.coverImage ?? info.thumb
        let alert = alertStore.alert(for: item.id)
        let isSelected = selectedItemIds.contains(item.id)

        return ZStack {
            NavigationLink(value: SearchDestination.release(item.id, coverURL: coverURL)) {
                AsyncCoverImage(url: coverURL, cornerRadius: 6, showsBorder: true, targetSize: 100)
                    .aspectRatio(1, contentMode: .fit)
                    .opacity(isSelecting ? (isSelected ? 1.0 : 0.45) : 1.0)
                    .overlay {
                        if isSelecting && isSelected {
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
                    .overlay(alignment: .bottomTrailing) {
                        if !isSelecting, let alert {
                            Image(systemName: alert.isTriggered ? "bell.badge.fill" : "bell.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(alert.isTriggered ? .green : Color.spinlogPink)
                                .padding(4)
                                .background(.ultraThinMaterial, in: Circle())
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
            Button {
                onAlertTap(item)
            } label: {
                Label(
                    alert != nil ? "Modifier l'alerte prix" : "Définir une alerte prix",
                    systemImage: alert != nil ? "bell.badge.fill" : "bell"
                )
            }
        })
    }
}
