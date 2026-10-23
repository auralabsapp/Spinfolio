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
    /// Hauteur mesurée du contenu, utilisée comme seul cran de la feuille.
    @State private var contentHeight: CGFloat = 420

    var body: some View {
        VStack(spacing: 18) {
            // Pochette entière devant un disque qui tourne : vinyle à étiquette ou CD argenté, selon le
            // support de l'album (voir `SpinningRecordArtwork`).
            SpinningRecordArtwork(coverURL: lastCoverURL, media: lastMedia, title: lastTitle, artist: lastArtist)

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
                    .accessibilityLabel("Voir la fiche du disque")
                }
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    await activityManager.endCurrentActivity()
                    dismiss()
                }
            } label: {
                Label("Arrêter l'écoute", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(Color.spinlogPink)
            .padding(.top, 4)
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .onAppear(perform: rememberCurrentAlbum)
        .onChange(of: activityManager.activeAlbumTitle) { rememberCurrentAlbum() }
        .onChange(of: activityManager.activeReleaseId) { _, id in
            // Écoute terminée ailleurs (Live Activity, autre écran) : plus rien à afficher.
            if id == nil { dismiss() }
        }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
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
