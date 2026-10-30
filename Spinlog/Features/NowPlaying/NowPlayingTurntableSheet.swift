import SwiftUI

/// Petite feuille ouverte depuis le mini-lecteur pendant une écoute sur platine : jaquette, titre
/// de l'album, artiste, accès à la fiche du disque et un seul bouton de lecture, « Arrêter l'écoute ». Sa hauteur épouse son contenu (pas
/// d'espace vide en bas), contrairement à la fenêtre plein écran d'une lecture Apple Music, qui a
/// des pistes et des commandes.
struct NowPlayingTurntableSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var activityManager = NowPlayingActivityManager.shared

    /// Dernier album connu : à l'arrêt de l'écoute, les valeurs du gestionnaire repassent à `nil`
    /// avant la fin de l'animation de fermeture, et la feuille ne doit pas se vider d'un coup.
    @State private var lastTitle = ""
    @State private var lastArtist = ""
    @State private var lastCoverURL: String?
    @State private var lastReleaseId: Int?
    /// Support de l'album (vinyle ou CD), qui décide du disque dessiné derrière la pochette.
    @State private var lastMedia: PhysicalMedia = .vinyl
    /// Faux dès que l'écoute s'arrête : le disque ralentit et le bras se relève avant la fermeture.
    @State private var isPlayingVisual = true
    @State private var isClosing = false
    /// Stop demandé depuis la feuille : l'écoute s'arrête à sa disparition (voir `stopAndClose`).
    @State private var endsListeningOnDisappear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Hauteur mesurée du contenu, utilisée comme seul cran de la feuille.
    @State private var contentHeight: CGFloat = 420

    var body: some View {
        VStack(spacing: 18) {
            // Pochette entière devant un disque qui tourne : vinyle à étiquette ou CD argenté, selon le
            // support de l'album (voir `SpinningRecordArtwork`).
            SpinningRecordArtwork(
                coverURL: lastCoverURL,
                media: lastMedia,
                title: lastTitle,
                artist: lastArtist,
                isPlaying: isPlayingVisual
            )

            // Même disposition que la fenêtre Apple Music : titre et artiste à gauche, accès à la
            // fiche du disque à droite.
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lastTitle)
                        .font(.title3.bold())
                        .lineLimit(2)
                    if !lastArtist.isEmpty {
                        Text(lastArtist)
                            .font(.title3)
                            .foregroundStyle(Color.appSecondaryText)
                            .lineLimit(1)
                    }
                    Text("Écoute sur platine")
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondaryText)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                if let releaseId = lastReleaseId {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                        TabNavigationCoordinator.shared.returnToRelease(releaseId: releaseId, coverURL: lastCoverURL)
                    } label: {
                        Image(systemName: "opticaldisc")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Voir la fiche de l'album")
                }
            }

            Button {
                stopAndClose()
            } label: {
                Label("Arrêter l'écoute", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(Color.onAccent)
            .buttonBorderShape(.capsule)
            .tint(Color.spinlogPink)
            .padding(.top, 4)
            .disabled(isClosing)
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        // Closure de géométrie appelée hors du fil principal par SwiftUI : `@Sendable` (§12).
        .onGeometryChange(for: CGFloat.self) { @Sendable proxy in proxy.size.height } action: { contentHeight = $0 }
        .onAppear(perform: rememberCurrentAlbum)
        .onDisappear {
            guard endsListeningOnDisappear else { return }
            Task { await NowPlayingActivityManager.shared.endCurrentActivity() }
        }
        .onChange(of: activityManager.activeAlbumTitle) { rememberCurrentAlbum() }
        .onChange(of: activityManager.activeReleaseId) { _, id in
            // Écoute terminée ailleurs (Live Activity, autre écran) : même arrêt en douceur.
            if id == nil { closeGracefully() }
        }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
    }

    /// Fait ralentir le disque et relever le bras, puis ferme la feuille. Sans animations, elle se ferme
    /// presque aussitôt.
    private func closeGracefully() {
        guard !isClosing else { return }
        isClosing = true
        isPlayingVisual = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 1500))
            dismiss()
        }
    }

    /// Stop : le disque ralentit et le bras se relève, puis la feuille se réduit dans le mini-lecteur
    /// (zoom inverse de l'ouverture), et seulement une fois la feuille partie (`onDisappear`)
    /// l'écoute s'arrête et le mini-lecteur s'efface. Arrêter plus tôt retirait la cible du zoom en
    /// pleine fermeture : l'écran s'assombrissait un instant.
    private func stopAndClose() {
        guard !isClosing else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isClosing = true
        isPlayingVisual = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 1500))
            endsListeningOnDisappear = true
            dismiss()
        }
    }

    private func rememberCurrentAlbum() {
        guard activityManager.activeReleaseId != nil else { return }
        lastTitle = activityManager.activeAlbumTitle ?? String(localized: "Album vinyle")
        lastArtist = activityManager.activeArtistName ?? ""
        lastCoverURL = activityManager.activeCoverURL
        lastReleaseId = activityManager.activeReleaseId
        lastMedia = Self.media(forReleaseId: activityManager.activeReleaseId)
    }

    /// Support d'après les formats déjà connus localement (collection, sinon wantlist) ; vinyle par
    /// défaut quand le disque n'y est pas, comme avant l'ajout du CD.
    private static func media(forReleaseId releaseId: Int?) -> PhysicalMedia {
        guard let releaseId, let username = DiscogsAuthManager.shared.username else { return .vinyl }
        let store = LocalDataStore.shared
        let formats = store.getCollectionItems(username: username, releaseId: releaseId).first?.basicInformation.formats
            ?? store.getWantlistItem(username: username, releaseId: releaseId)?.basicInformation.formats
        return PhysicalMedia.from(formatNames: (formats ?? []).map(\.name))
    }
}
