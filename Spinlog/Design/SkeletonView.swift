import SwiftUI

/// Bloc neutre (rectangle arrondi) utilisé comme gabarit de chargement : reproduit la forme du
/// contenu réel à venir (ligne de texte, pochette, carte…) à la même place, pour que l'apparition
/// des vraies données ne fasse pas sauter la mise en page. Un halo lumineux tourne en boucle le
/// long de son contour (plutôt qu'un rayon qui le traverse) pour signaler la récupération en
/// cours, sans icône de chargement classique. La phase est calculée à partir de l'horloge
/// (`TimelineView`) plutôt que d'un `@State` animé individuellement : tous les blocs de la page
/// restent ainsi parfaitement synchronisés.
struct SkeletonBlock: View {
    var cornerRadius: CGFloat = 8
    var width: CGFloat? = nil
    var height: CGFloat? = nil

    private let duration: TimeInterval = 2.4

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: duration) / duration

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            AngularGradient(
                                colors: [.clear, .white.opacity(0.45), .clear],
                                center: .center,
                                startAngle: .degrees(t * 360 - 35),
                                endAngle: .degrees(t * 360 + 35)
                            ),
                            lineWidth: 1.25
                        )
                        .blendMode(.plusLighter)
                )
                .frame(width: width, height: height)
        }
    }
}

/// Section générique d'un squelette de page : un titre court puis un bloc de contenu, à l'image
/// d'un `SectionEyebrow` suivi d'une carte ou d'une liste dans une vraie fiche de détail.
/// Partagée par toutes les pages utilisant `SkeletonBlock` pour rester cohérentes entre elles.
struct SkeletonSection: View {
    var titleWidth: CGFloat = 160
    var contentHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(width: titleWidth, height: 14)
            SkeletonBlock(cornerRadius: 14, height: contentHeight)
        }
    }
}

/// Ligne neutre pour les squelettes d'affichage Liste (Collection/Wantlist) : pochette + lignes
/// de texte, à l'image de `CollectionRow`/`WantlistRow`. `lineCount` suit le nombre de lignes de
/// la vraie ligne qu'elle imite : 3 pour `CollectionRow` (titre, artiste, puis format/année/badges
/// selon les champs renseignés), 2 pour `WantlistRow` (titre, artiste seulement — pas de 3e ligne).
/// `coverSize` suit de même la taille réelle de la pochette (`CollectionRow.coverSize` ou
/// `WantlistRow.coverSize`, selon l'écran) — sans paramètre partagé, les deux pouvaient
/// silencieusement diverger (c'est déjà arrivé : la pochette de `WantlistRow` a rétréci à 56pt
/// sans que ce gabarit, resté à 80pt en dur, ne suive).
struct SkeletonLibraryRow: View {
    var lineCount: Int = 3
    var coverSize: CGFloat = CollectionRow.coverSize

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            SkeletonBlock(cornerRadius: 10, width: coverSize, height: coverSize)

            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(height: 16)
                SkeletonBlock(width: 140, height: 13)
                if lineCount > 2 {
                    SkeletonBlock(width: 90, height: 11)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

/// En-tête de section neutre pour les squelettes d'affichage Liste/Mosaïque, à l'image de
/// `LibrarySectionHeader` (jeton + titre + pastille de compte) — mêmes marges internes que ce
/// dernier pour occuper exactement la même hauteur, qu'il se place dans une `List` (via
/// `.listRowInsets`, ignoré hors de ce contexte) ou dans une grille.
struct SkeletonSectionHeaderRow: View {
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            SkeletonBlock(width: 20, height: 16)
            SkeletonBlock(width: 100, height: 14)
            Spacer()
            SkeletonBlock(cornerRadius: 9, width: 28, height: 18)
        }
        .padding(.vertical, 2)
        .padding(.trailing, 4)
        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
    }
}
