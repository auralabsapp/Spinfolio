import SwiftUI

/// Colonne centrale du guide de rangement : le disque à ranger, avec le repère « ICI », sa pochette
/// entourée d'un halo qui respire, son titre, son artiste et son année. Les états d'animation
/// (rebond au toucher, respiration de la pochette, battement du repère) viennent de `ShelfPlacementView`, qui
/// orchestre l'ensemble de l'écran ; cette vue ne fait que les afficher.
struct ShelfTargetColumn: View {
    let release: Release
    let yearText: String?
    let isPulsing: Bool
    let isCoverBreathing: Bool
    let isBadgeBeating: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var badgeScale: CGFloat {
        if isPulsing && !reduceMotion { return 1.15 }
        return isBadgeBeating ? 1.07 : 1
    }

    /// Respiration lente et permanente de la pochette (grossit puis reprend sa taille), à laquelle
    /// s'ajoute le petit rebond du toucher.
    private var coverScale: CGFloat {
        let breathing: CGFloat = isCoverBreathing ? 1.08 : 1
        let tap: CGFloat = isPulsing && !reduceMotion ? 1.06 : 1
        return breathing * tap
    }

    var body: some View {
        VStack(spacing: 8) {
            // Repère d'emplacement : volontairement à plat (ni fond plein, ni ombre), pour ne pas
            // ressembler à un bouton alors qu'il n'ouvre rien.
            HStack(spacing: 3) {
                Image(systemName: "arrow.down")
                    .font(.caption2.weight(.bold))
                Text("ICI")
                    .font(.caption2.weight(.heavy))
            }
            .foregroundStyle(Color.spinlogPink)
            .scaleEffect(badgeScale)

            // Pochette centrale plus grande avec bordure rose, sur un halo qui respire doucement.
            AsyncCoverImage(url: release.primaryImageURL, cornerRadius: 10, targetSize: 104)
                .frame(width: 104, height: 104)
                .background { BreathingGlow(cornerRadius: 12, blurRadius: 14) }
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.spinlogPink, lineWidth: isPulsing ? 4 : 2)
                )
                .shadow(color: Color.spinlogPink.opacity(isPulsing ? 0.5 : 0.25), radius: 8, y: 4)
                .scaleEffect(coverScale)

            // Titre, artiste et année
            VStack(spacing: 2) {
                Text(release.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !release.artistNames.isEmpty {
                    Text(release.artistNames)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.spinlogPink)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }

                if let yearText {
                    Text(yearText)
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.appSecondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        // Le toucher n'ouvre rien : pour VoiceOver, c'est un simple repère, lu d'un seul bloc.
        .accessibilityElement(children: .combine)
    }
}
