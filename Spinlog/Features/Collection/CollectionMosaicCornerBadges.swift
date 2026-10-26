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
