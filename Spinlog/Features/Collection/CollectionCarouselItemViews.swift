import SwiftUI

/// Pastilles sous la pochette au centre du carrousel Collection : numéro d'exemplaire et note.
struct CollectionCarouselBadges: View {
    let copyBadge: String?
    let rating: Int
    let isRegularDisplay: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let copyBadge {
                Text(copyBadge)
                    .font(isRegularDisplay ? .footnote.bold() : .caption2.bold())
                    .padding(.horizontal, isRegularDisplay ? 9 : 7)
                    .padding(.vertical, isRegularDisplay ? 3 : 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }

            if rating > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.inlineIcon)
                        .foregroundStyle(Color.orange)
                    Text("\(rating)")
                        .font(isRegularDisplay ? .footnote.bold() : .caption2.bold())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 2)
    }
}

/// Boutons ronds sous la pochette au centre du carrousel Collection : écoute sur platine
/// (démarrer ou arrêter), guide de rangement, modification de la note et des commentaires.
struct CollectionCarouselQuickActions: View {
    let isPlaying: Bool
    let isRegularDisplay: Bool
    let onToggleListening: () -> Void
    let onShowShelf: () -> Void
    let onEdit: () -> Void

    private var side: CGFloat { isRegularDisplay ? 46 : 38 }
    private var iconSize: CGFloat { isRegularDisplay ? 17 : 14 }

    var body: some View {
        HStack(spacing: isRegularDisplay ? 16 : 12) {
            Button(action: onToggleListening) {
                Image(systemName: isPlaying ? "stop.fill" : "opticaldisc.fill")
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(isPlaying ? .white : Color.spinlogPink)
                    .frame(width: side, height: side)
                    .expandedHitArea(visibleSide: side)
                    .background(isPlaying ? Color(uiColor: .systemGray) : Color.spinlogPinkBadge, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? Text("Arrêter l'écoute") : Text("J'écoute ce disque sur la platine"))

            Button(action: onShowShelf) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: side, height: side)
                    .expandedHitArea(visibleSide: side)
                    .background(Color.indigo.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Où ranger ce disque")

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(Color.appSecondaryText)
                    .frame(width: side, height: side)
                    .expandedHitArea(visibleSide: side)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Modifier la note et les commentaires")
        }
    }
}
