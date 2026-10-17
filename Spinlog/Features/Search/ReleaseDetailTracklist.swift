import SwiftUI

/// Section tracklist et bouton de lecture Apple Music par piste de la fiche release —
/// extrait de ReleaseDetailView.swift, voir le commentaire sur `ReleaseDetailSheets`.
struct TracklistSection: View {
    let tracklist: [Track]
    let artistName: String
    let albumTitle: String
    var coverURL: String? = nil
    var destination: SearchDestination? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionEyebrow(title: "Titres", icon: "music.note.list", style: .subsection)
                Spacer()
                if tracklist.contains(where: { !$0.isHeading }) {
                    Text("Lecture sur Apple Music")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(tracklist.enumerated()), id: \.element.id) { index, track in
                    HStack(alignment: .center, spacing: 10) {
                        if track.isHeading {
                            Image(systemName: "music.note")
                                .font(.caption2)
                                .foregroundStyle(Color.spinlogPink)
                                .frame(width: 22, height: 22)
                                .background(Color.spinlogPinkBadge, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        Text(track.position)
                            .font(.caption)
                            .foregroundStyle(Color.appSecondaryText)
                            .frame(width: 28, alignment: .leading)
                        Text(track.title)
                            .font(.subheadline)
                        Spacer()
                        if track.isHeading {
                            if let duration = track.duration, !duration.isEmpty {
                                Text(duration).font(.caption).foregroundStyle(Color.appSecondaryText)
                            }
                        } else {
                            TrackPlayButton(
                                trackID: track.id,
                                artistName: artistName,
                                albumTitle: albumTitle,
                                trackTitle: track.title,
                                duration: track.duration,
                                coverURL: coverURL,
                                destination: destination
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    if index < tracklist.count - 1 {
                        Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 14)
                    }
                }

                if let totalDuration {
                    Divider().overlay(Color.appSeparator).opacity(0.15)
                    HStack {
                        Text("Durée totale").font(.subheadline.bold())
                        Spacer()
                        Text(totalDuration).font(.subheadline).foregroundStyle(Color.appSecondaryText)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var totalDuration: String? {
        let totalSeconds = tracklist.compactMap { seconds(from: $0.duration) }.reduce(0, +)
        guard totalSeconds > 0 else { return nil }
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func seconds(from duration: String?) -> Int? {
        guard let duration, let colonIndex = duration.firstIndex(of: ":") else { return nil }
        let minutesPart = duration[..<colonIndex]
        let secondsPart = duration[duration.index(after: colonIndex)...]
        guard let minutes = Int(minutesPart), let seconds = Int(secondsPart) else { return nil }
        return minutes * 60 + seconds
    }
}

/// Bouton de lecture placé en face de chaque titre de la tracklist : extrait de 30s par défaut,
/// ou morceau complet si Apple Music est connecté avec un abonnement actif (voir
/// `AppleMusicAccountStore` dans Réglages). Reste simplement inopérant si aucune correspondance
/// n'est trouvée dans le catalogue Apple Music — pas d'état d'erreur visible pour ce qui reste une
/// fonctionnalité décorative.
private struct TrackPlayButton: View {
    let trackID: String
    let artistName: String
    let albumTitle: String
    let trackTitle: String
    let duration: String?
    var coverURL: String? = nil
    var destination: SearchDestination? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var service = AppleMusicPlaybackService.shared

    private var isPlaying: Bool { service.playingTrackID == trackID }
    private var isLoading: Bool { service.isLoadingTrackID == trackID }
    /// `nil` tant que la correspondance n'a pas encore été vérifiée (voir `.task` ci-dessous).
    private var matchStatus: Bool? { service.matchStatus(for: trackID) }
    private var hasMatch: Bool { matchStatus == true }

    /// Teinte Apple Music adaptée au thème :
    /// - Thème sombre : rouge adouci et profond
    /// - Thème clair : rouge plus lumineux pour ne pas paraître trop sombre sur fond clair
    private var appleMusicRed: Color {
        colorScheme == .dark
            ? Color(red: 222 / 255, green: 56 / 255, blue: 72 / 255)
            : Color(red: 246 / 255, green: 66 / 255, blue: 84 / 255)
    }

    /// Couleur de secours pour l'indicateur de chargement alignée sur l'arrière-plan.
    private var symbolColor: Color {
        Color.appBackground
    }

    var body: some View {
        HStack(spacing: 8) {
            if let duration, !duration.isEmpty {
                Text(duration)
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            }

            // Petite forme d'onde animée façon Apple Music visible uniquement pendant la lecture
            if isPlaying {
                Image(systemName: "waveform")
                    .font(.inlineIcon)
                    .foregroundStyle(appleMusicRed)
                    .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.5).combined(with: .opacity).combined(with: .move(edge: .trailing)),
                            removal: .scale(scale: 0.5).combined(with: .opacity).combined(with: .move(edge: .trailing))
                        )
                    )
            }

            Button {
                Task {
                    await service.toggle(
                        trackID: trackID,
                        artistName: artistName,
                        albumTitle: albumTitle,
                        trackTitle: trackTitle,
                        trackDuration: duration,
                        coverURL: coverURL,
                        destination: destination,
                        sourceTab: TabNavigationCoordinator.shared.selectedTab
                    )
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(matchStatus == false ? appleMusicRed.opacity(0.35) : appleMusicRed)
                        .frame(width: 20, height: 20)

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.48)
                            .tint(symbolColor)
                    } else if isPlaying {
                        Image(systemName: "pause.fill")
                            .font(.coverCornerBadge)
                            .blendMode(.destinationOut)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.coverCornerBadge)
                            .offset(x: 0.6)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
                .frame(width: 26, height: 26)
                .contentShape(Circle())
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.78), value: isPlaying)
        .buttonStyle(.plain)
        .disabled(matchStatus == false)
        .task(id: trackID) {
            await service.prefetchMatch(trackID: trackID, artistName: artistName, albumTitle: albumTitle, trackTitle: trackTitle, trackDuration: duration)
        }
        .accessibilityLabel(isPlaying ? Text("Mettre en pause \(trackTitle)") : Text("Lire \(trackTitle) sur Apple Music"))
    }
}
