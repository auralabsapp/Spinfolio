import SwiftUI

/// Pastilles posées aux coins d'une pochette de la mosaïque Collection : numéro d'exemplaire en
/// haut à droite, écoute en cours en bas à gauche, note en bas à droite.
struct CollectionMosaicCornerBadges: View {
    let copyBadge: String?
    let isPlaying: Bool
    let rating: Int

    var body: some View {
        Color.clear
            .overlay(alignment: .topTrailing) {
                if let copyBadge {
                    Text(copyBadge)
                        .font(.coverCornerBadge)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.7), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isPlaying {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform")
                            .font(.coverCornerBadge)
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
                if rating > 0 {
                    HStack(spacing: 1.5) {
                        Image(systemName: "star.fill")
                            .font(.coverCornerBadge)
                            .foregroundStyle(Color.orange)
                        Text("\(rating)")
                            .font(.coverCornerBadge)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.65), in: Capsule())
                    .padding(4)
                }
            }
    }
}

/// Mise en valeur du disque tiré au hasard (« Disque au hasard »), le temps qu'il soit repéré.
enum CollectionRandomPickHighlight {
    /// Fond de la ligne en mode Liste.
    static var row: some View {
        Color.spinlogPink.opacity(0.18)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.spinlogPink.opacity(0.6), lineWidth: 1.5)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            )
    }

    /// Contour de la pochette en mode Mosaïque.
    static var cover: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Color.spinlogPink, lineWidth: 3)
            .shadow(color: Color.spinlogPink.opacity(0.6), radius: 6)
    }
}
