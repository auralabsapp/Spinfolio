import SwiftUI

/// Jaquette en plein bord en haut de la fiche disque : parallaxe, flou progressif et étirement
/// à la traction vers le bas. Dépend du `coordinateSpace(name: "releaseScroll")` posé sur le
/// `ScrollView` de `ReleaseDetailView`.
struct ReleaseHeroCover: View {
    let release: Release
    let releaseId: Int
    let initialCoverURL: String?
    let backgroundColor: Color
    /// Change à chaque ajout à la collection ou à la wantlist : déclenche le léger « pop ».
    let heroPop: Int
    let onAverageColor: (UIColor) -> Void
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .named("releaseScroll")).minY
            let width = proxy.size.width
            let height = width

            // Détection du scroll vers le haut (swipe up) : minY < 0
            let scrollUp = max(0, -minY)
            // Étirement fluide si traction vers le bas (pull-down rubberband) : minY > 0
            let pullDown = max(0, minY)

            // Progression du swipe up étalée sur toute la hauteur de la jaquette
            let maxDistance = max(1.0, height * 1.0)
            let rawProgress = min(1.0, scrollUp / maxDistance)

            // Courbe progressive douce (puissance 1.6) :
            // La jaquette conserve sa netteté au début du scroll, puis s'adoucit très délicatement
            let easedProgress = pow(rawProgress, 1.6)

            // Floutage progressif : de 0 pt (net) à 30 pt (ambiance fluide et colorée)
            let blurRadius = easedProgress * 30.0

            // Effet parallaxe : la jaquette monte 2 fois moins vite que le défilement (désactivé
            // avec Réduire les animations : elle défile alors avec le contenu).
            let parallaxOffset = reduceMotion ? 0 : scrollUp * 0.5

            ZStack {
                // Fond teinté de la couleur moyenne pour éviter tout blanchiment en arrière-plan
                backgroundColor

                AsyncCoverImage(
                    url: release.primaryImageURL ?? initialCoverURL,
                    cornerRadius: 0,
                    showsBorder: false,
                    onAverageColorLoaded: { color in
                        ReleaseColorCache.shared.register(color: color, forReleaseId: releaseId, url: release.primaryImageURL)
                        onAverageColor(color)
                    }
                )
                .aspectRatio(1, contentMode: .fill)
                .frame(width: width, height: height + pullDown, alignment: .top)
                .scaleEffect(1.0 + easedProgress * 0.10) // Empêche les bords blanchis par le flou
                .libraryPop(trigger: heroPop, peak: 1.04)
                .blur(radius: blurRadius)
                .clipped()
            }
            .frame(width: width, height: height + pullDown, alignment: .top)
            .clipped()
            .offset(y: -pullDown + parallaxOffset)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityLabel("Pochette de l'album")
        .accessibilityHint("Voir en plein écran")
        .accessibilityAddTraits(.isButton)
    }
}

/// Titre de l'album et crédits d'artistes superposés à la jaquette : chaque artiste est un lien
/// vers sa fiche (`ArtistDetailView`), séparés par le connecteur Discogs (`join`, ex : « & »,
/// « Featuring ») en texte brut non cliquable — même principe que `CreditsSection`. Non-wrapping
/// par simplicité (la quasi-totalité des releases ont 1 à 3 artistes) ; au-delà, le nom tronque
/// proprement plutôt que de retourner à la ligne.
struct ReleaseArtistCreditsRow: View {
    let artists: [ReleaseArtist]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(artists.enumerated()), id: \.offset) { index, artist in
                NavigationLink(value: SearchDestination.artist(artist.id)) {
                    Text(artist.displayName)
                }
                .buttonStyle(.plain)

                if index < artists.count - 1 {
                    let join = artist.join?.trimmingCharacters(in: .whitespaces) ?? ""
                    Text(join.isEmpty ? "," : join)
                }
            }
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(.white.opacity(0.92))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .shadow(color: .black.opacity(0.9), radius: 3, x: 0, y: 1)
        .shadow(color: .black.opacity(0.7), radius: 14, x: 0, y: 4)
        .frame(maxWidth: .infinity)
    }
}

/// Gabarit neutre affiché pendant le chargement, à la place d'une icône de chargement :
/// pochette en plein bord (comme la vraie jaquette héro, pas de titre/artiste superposé tant
/// qu'on ne l'a pas), les 2 boutons d'action, puis des sections génériques titre + contenu
/// (voir `SkeletonBlock`), pour que l'apparition du contenu réel ne fasse pas sauter la page.
struct ReleaseDetailSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SkeletonBlock(cornerRadius: 0)
                    .aspectRatio(1, contentMode: .fit)
                    .padding(.bottom, 24)

                VStack(alignment: .leading, spacing: 32) {
                    HStack(spacing: 10) {
                        SkeletonBlock(cornerRadius: 21, height: 42)
                        SkeletonBlock(cornerRadius: 21, height: 42)
                    }

                    SkeletonSection(contentHeight: 70)
                    SkeletonSection(contentHeight: 130)
                    SkeletonSection(contentHeight: 160)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollDisabled(true)
    }
}
