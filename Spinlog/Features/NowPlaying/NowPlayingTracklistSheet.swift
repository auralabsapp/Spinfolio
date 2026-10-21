import SwiftUI

/// Liste des pistes de l'album en cours, ouverte depuis le bouton « liste » de la fenêtre de
/// lecture (équivalent de la file d'attente d'Apple Music) : piste en cours repérée, toucher pour
/// lancer une autre piste (Apple Music seulement).
struct NowPlayingTracklistSheet: View {
    let album: NowPlayingAlbum?
    let isLoading: Bool
    let loadFailed: Bool
    /// Titre Apple Music en cours (`nil` en écoute sur platine : pistes affichées, non jouables).
    let playingItem: NowPlayingItem?
    let onPlay: (Track) -> Void

    @State private var service = AppleMusicPlaybackService.shared
    @State private var networkMonitor = NetworkMonitor.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Titres")
                    .font(.headline)
                Spacer()
                SheetCloseButton()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let tracks = album?.tracklist, !tracks.isEmpty {
                        ForEach(tracks) { track in
                            trackRow(track)
                            Divider().overlay(Color.white.opacity(0.15))
                        }
                    } else if isLoading {
                        ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 80)
                    } else if loadFailed {
                        Text(networkMonitor.isConnected
                             ? "La liste des pistes n'a pas pu être chargée."
                             : "La liste des pistes est indisponible hors ligne.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .foregroundStyle(.white)
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func trackRow(_ track: Track) -> some View {
        if track.isHeading {
            Text(track.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 14)
                .padding(.bottom, 6)
        } else {
            let isCurrent = playingItem?.trackID == track.id
            let isUnavailable = service.matchStatus(for: track.id) == false
            let row = HStack(spacing: 12) {
                ZStack {
                    if isCurrent {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
                    } else {
                        Text(track.position).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .font(.footnote)
                .frame(width: 32, alignment: .leading)

                Text(track.title)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let duration = track.duration, !duration.isEmpty {
                    Text(duration)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.vertical, 12)
            .opacity(isUnavailable ? 0.4 : 1)
            .contentShape(Rectangle())

            if let playingItem {
                row
                    .onTapGesture { onPlay(track) }
                    .task(id: track.id) {
                        await service.prefetchMatch(
                            trackID: track.id,
                            artistName: playingItem.artistName,
                            albumTitle: playingItem.albumTitle,
                            trackTitle: track.title,
                            trackDuration: track.duration
                        )
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction(named: Text("Lire \(track.title) sur Apple Music")) { onPlay(track) }
            } else {
                row.accessibilityElement(children: .combine)
            }
        }
    }
}
