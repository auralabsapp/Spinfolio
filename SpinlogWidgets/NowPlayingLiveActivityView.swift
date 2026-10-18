import SwiftUI
import WidgetKit
import ActivityKit

/// Composant de disque vinyle pour la Dynamic Island et le Lock Screen.

/// Couleur du thème de l'app, publiée par `ThemeManager` dans l'App Group. Repli sur le rose
/// historique tant que l'app n'a jamais été ouverte depuis cette version.
private enum NowPlayingThemeColor {
    static var accent: Color {
        WidgetSnapshotStore.themeAccentOnDark ?? Color(red: 232/255, green: 76/255, blue: 139/255)
    }
}

struct SpinningVinylIcon: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            // Disque noir avec rainures
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(white: 0.22),
                            Color(white: 0.05),
                            Color(white: 0.16),
                            Color(white: 0.05)
                        ]),
                        center: .center,
                        startRadius: 2,
                        endRadius: size / 2
                    )
                )
                .frame(width: size, height: size)

            // Rainure stylisée
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                .frame(width: size * 0.65, height: size * 0.65)

            // Macaron central à la couleur du thème
            Circle()
                .fill(NowPlayingThemeColor.accent)
                .frame(width: size * 0.38, height: size * 0.38)

            // Trou central
            Circle()
                .fill(Color.black)
                .frame(width: size * 0.12, height: size * 0.12)
        }
    }
}

/// Vue miniature pour afficher la jaquette d'album ou le disque vinyle en repli
struct AlbumCoverOrVinylView: View {
    let imageData: Data?
    let size: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        if let imageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(white: 0.12))
                    .frame(width: size, height: size)

                SpinningVinylIcon(size: size * 0.75)
            }
        }
    }
}

/// Contenu principal partagé à l'identique entre le Lock Screen et la Dynamic Island étendue.
struct NowPlayingContentRow: View {
    let releaseId: Int
    let albumTitle: String
    let artistName: String
    let imageData: Data?
    var coverSize: CGFloat = 54
    var cornerRadius: CGFloat = 10
    var stopButtonSize: CGFloat = 36
    /// Durée d'écoute maximale dépassée (`context.isStale`) : l'app, suspendue, n'a pas pu fermer
    /// l'activité à temps. On l'affiche comme terminée plutôt que « en cours » pendant des heures.
    var isEnded: Bool = false

    private var accentColor: Color {
        isEnded ? Color.white.opacity(0.55) : NowPlayingThemeColor.accent
    }

    var body: some View {
        HStack(spacing: 14) {
            // Jaquette de la release
            AlbumCoverOrVinylView(
                imageData: imageData,
                size: coverSize,
                cornerRadius: cornerRadius
            )
            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)

            // Textes : indicateur d'écoute sur platine, titre, artiste
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 6, height: 6)

                    // Libellé localisé par l'extension elle-même : `ContentState.statusText`,
                    // fourni par l'app, s'affichait tel quel (toujours en français).
                    Text(isEnded ? "Écoute terminée" : "Écoute en cours sur la platine")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Text(albumTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(artistName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Bouton Stop (icône carrée seule dans une pastille circulaire)
            Link(destination: URL(string: "spinlog://end-session/\(releaseId)")!) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: stopButtonSize, height: stopButtonSize)
                    .background(Color.white.opacity(0.18), in: Circle())
            }
            .accessibilityLabel("Arrêter l'écoute")
        }
    }
}

/// Définition du Widget Live Activity & Dynamic Island.
struct NowPlayingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingActivityAttributes.self) { context in
            // MARK: - Lock Screen & Bannière étendue
            NowPlayingContentRow(
                releaseId: context.attributes.releaseId,
                albumTitle: context.attributes.albumTitle,
                artistName: context.attributes.artistName,
                imageData: context.state.coverImageData,
                coverSize: 56,
                cornerRadius: 10,
                stopButtonSize: 38,
                isEnded: context.isStale
            )
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.85))

        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Dynamic Island Étendue (appui long)
                // Même disposition identique avec icône Stop carrée sans libellé
                DynamicIslandExpandedRegion(.bottom) {
                    NowPlayingContentRow(
                        releaseId: context.attributes.releaseId,
                        albumTitle: context.attributes.albumTitle,
                        artistName: context.attributes.artistName,
                        imageData: context.state.coverImageData,
                        coverSize: 50,
                        cornerRadius: 9,
                        stopButtonSize: 34,
                        isEnded: context.isStale
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }

            } compactLeading: {
                // MARK: - Dynamic Island Compacte (Côté gauche : Jaquette de l'album !)
                if let data = context.state.coverImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(.leading, 2)
                } else {
                    SpinningVinylIcon(size: 18)
                        .padding(.leading, 2)
                }

            } compactTrailing: {
                // MARK: - Dynamic Island Compacte (Côté droit : vinyle)
                SpinningVinylIcon(size: 18)
                    .padding(.trailing, 2)

            } minimal: {
                // MARK: - Dynamic Island Minimale
                if let data = context.state.coverImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                } else {
                    SpinningVinylIcon(size: 16)
                }
            }
            .widgetURL(URL(string: "spinlog://release/\(context.attributes.releaseId)"))
            .keylineTint(NowPlayingThemeColor.accent)
        }
    }
}
