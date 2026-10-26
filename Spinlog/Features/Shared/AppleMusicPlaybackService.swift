import Foundation
import MusicKit
import AVFoundation
import Observation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "AppleMusicPlayback")

/// Lit un titre de la tracklist d'une fiche release : extrait de 30s par défaut, ou morceau
/// complet si `AppleMusicAccountStore` signale un compte Apple Music connecté avec un abonnement
/// actif. Purement décoratif comme `AppleMusicArtistArtworkService` : en l'absence de
/// correspondance dans le catalogue, le bouton de lecture reste simplement inopérant.
@MainActor
@Observable
final class AppleMusicPlaybackService {
    static let shared = AppleMusicPlaybackService()

    /// Identifiant (voir `Track.id`) du titre en cours de lecture ou en pause, `nil` si rien
    /// n'est chargé.
    private(set) var playingTrackID: String?
    private(set) var isLoadingTrackID: String?
    private(set) var currentItem: NowPlayingItem?
    private(set) var playbackTime: TimeInterval = 0
    private(set) var totalDuration: TimeInterval = 0

    var isPlaying: Bool { playingTrackID != nil }

    var playbackProgress: Double {
        guard totalDuration > 0 else { return 0 }
        return min(max(playbackTime / totalDuration, 0), 1)
    }

    private var previewPlayer: AVPlayer?
    private var previewEndObserver: NSObjectProtocol?
    private var timeObserverToken: Any?
    private var progressPollingTask: Task<Void, Never>?
    /// Cache des correspondances déjà recherchées, par artiste+album+titre — évite de redemander
    /// la même recherche à chaque fois qu'on rouvre la même fiche release.
    private var songCache: [String: MusicKit.Song?] = [:]
    /// `nil` : pas encore vérifié. `true` : correspondance trouvée. `false` : aucune — le bouton
    /// de lecture de ce titre reste grisé et inactif (voir `TrackPlayButton`).
    private var matchStatusByTrackID: [String: Bool] = [:]
    /// Chaîne les préchargements les uns après les autres plutôt que de les laisser partir tous
    /// en même temps (voir `prefetchMatch`).
    private var prefetchChain: Task<Void, Never>?

    private init() {}

    func matchStatus(for trackID: String) -> Bool? {
        matchStatusByTrackID[trackID]
    }

    /// Résout la correspondance Apple Music dès l'affichage de la ligne, sans déclencher de
    /// lecture — permet de griser immédiatement les titres sans correspondance plutôt que
    /// d'attendre un appui pour le découvrir. N'interroge que le statut d'autorisation déjà connu
    /// (ne demande jamais l'invite système ici) : un affichage de page ne doit pas provoquer de
    /// demande de permission à l'insu de l'utilisateur, seul un vrai appui sur le bouton le fait.
    ///
    /// Chaque ligne de la tracklist déclenche son propre préchargement dès son affichage (voir
    /// `TrackPlayButton.task`), et comme la tracklist entière apparaît d'un coup (pas de
    /// défilement paresseux), une dizaine de recherches MusicKit partaient auparavant en même
    /// temps — jusqu'à une centaine de morceaux candidats décodés et notés sur l'acteur principal
    /// dans la même fraction de seconde, observé comme une rafale d'avertissements internes
    /// MediaPlayer corrélée à des gels ponctuels de l'app. On les enchaîne maintenant une par
    /// une : le coût total reste le même, mais réparti dans le temps au lieu d'une seule rafale.
    func prefetchMatch(trackID: String, artistName: String, albumTitle: String, trackTitle: String, trackDuration: String? = nil) async {
        guard matchStatusByTrackID[trackID] == nil else { return }
        let previous = prefetchChain
        let task = Task { [weak self] in
            _ = await previous?.value
            guard let self else { return }
            _ = await self.song(trackID: trackID, artistName: artistName, albumTitle: albumTitle, trackTitle: trackTitle, trackDuration: trackDuration, requestAuthorizationIfNeeded: false)
        }
        prefetchChain = task
        await task.value
    }

    func toggle(
        trackID: String,
        artistName: String,
        albumTitle: String,
        trackTitle: String,
        trackDuration: String? = nil,
        coverURL: String? = nil,
        destination: SearchDestination? = nil,
        sourceTab: AppTab? = nil
    ) async {
        if playingTrackID == trackID {
            stop()
            return
        }

        stop()
        isLoadingTrackID = trackID

        let found = await song(trackID: trackID, artistName: artistName, albumTitle: albumTitle, trackTitle: trackTitle, trackDuration: trackDuration, requestAuthorizationIfNeeded: true)
        // Un autre titre a été demandé pendant la recherche : celui-ci est abandonné. Sans cette
        // vérification, appuyer sur A puis aussitôt sur B finissait par lancer A aussi (deux
        // lecteurs simultanés, et un mini-lecteur affichant le mauvais titre).
        guard isLoadingTrackID == trackID else { return }
        guard let song = found else {
            isLoadingTrackID = nil
            return
        }

        if AppleMusicAccountStore.shared.canPlayFullCatalog {
            await playFull(song)
            guard isLoadingTrackID == trackID else {
                // Arrêté pendant le démarrage, sans autre titre demandé entre-temps : la lecture
                // vient de partir sans aucune interface pour l'arrêter.
                if playingTrackID == nil && isLoadingTrackID == nil {
                    progressPollingTask?.cancel()
                    ApplicationMusicPlayer.shared.pause()
                }
                return
            }
        } else {
            playPreview(song)
        }

        let resolvedTab = sourceTab ?? TabNavigationCoordinator.shared.selectedTab

        withAnimation(.nowPlayingTransition) {
            playingTrackID = trackID
            isLoadingTrackID = nil
            currentItem = NowPlayingItem(
                trackID: trackID,
                trackTitle: trackTitle,
                artistName: artistName,
                albumTitle: albumTitle,
                coverURL: coverURL,
                destination: destination,
                sourceTab: resolvedTab
            )
        }
    }

    func stop() {
        // Annule aussi une lecture en cours de préparation (voir la vérification dans `toggle`).
        isLoadingTrackID = nil
        guard isPlaying || currentItem != nil || previewPlayer != nil else { return }

        if let timeObserverToken {
            previewPlayer?.removeTimeObserver(timeObserverToken)
        }
        timeObserverToken = nil
        previewPlayer?.pause()
        if let previewEndObserver {
            NotificationCenter.default.removeObserver(previewEndObserver)
        }
        previewEndObserver = nil
        previewPlayer = nil
        progressPollingTask?.cancel()
        progressPollingTask = nil

        enqueueAudioSessionChange(active: false)

        if AppleMusicAccountStore.shared.canPlayFullCatalog {
            Task.detached(priority: .userInitiated) {
                ApplicationMusicPlayer.shared.pause()
            }
        }
        withAnimation(.nowPlayingTransition) {
            playingTrackID = nil
            currentItem = nil
            playbackTime = 0
            totalDuration = 0
        }
    }

    /// Arrêt en douceur depuis la fenêtre de lecture : le son de l'extrait baisse en fondu pendant
    /// que la fenêtre rentre dans le mini-lecteur, puis `stop()`. `ApplicationMusicPlayer` (morceau
    /// complet) n'a pas de réglage de volume : il s'arrête simplement à la fin du fondu. Rien n'est
    /// arrêté si un autre titre a été lancé entre-temps.
    func fadeOutAndStop(over duration: TimeInterval) async {
        let trackID = playingTrackID
        let steps = 12
        if let player = previewPlayer {
            let startVolume = player.volume
            for step in 1...steps {
                try? await Task.sleep(for: .seconds(duration / Double(steps)))
                guard previewPlayer === player else { return }
                player.volume = startVolume * Float(1 - Double(step) / Double(steps))
            }
        } else {
            try? await Task.sleep(for: .seconds(duration))
        }
        guard playingTrackID == trackID else { return }
        stop()
    }

    /// Déplace la tête de lecture à une position temporelle précise (en secondes).
    func seek(to seconds: TimeInterval) {
        guard totalDuration > 0 else { return }
        let clampedSeconds = max(0, min(seconds, totalDuration))
        playbackTime = clampedSeconds
        if let previewPlayer {
            let cmTime = CMTime(seconds: clampedSeconds, preferredTimescale: 600)
            previewPlayer.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
            previewPlayer.playImmediately(atRate: 1.0)
        } else if AppleMusicAccountStore.shared.canPlayFullCatalog {
            ApplicationMusicPlayer.shared.playbackTime = clampedSeconds
        }
    }

    private func playPreview(_ song: MusicKit.Song) {
        guard let url = song.previewAssets?.first?.url else { return }
        Task { @MainActor in
            await NowPlayingActivityManager.shared.endCurrentActivity()
        }
        totalDuration = 30.0
        playbackTime = 0

        enqueueAudioSessionChange(active: true)

        let player = AVPlayer(url: url)
        player.volume = 1.0
        previewPlayer = player

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.playbackTime = time.seconds
            }
        }

        previewEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                AppleMusicPlaybackService.shared.stop()
            }
        }
        player.playImmediately(atRate: 1.0)
    }

    /// Dernière modification de la session audio demandée, pour les enchaîner dans l'ordre.
    private var audioSessionTask: Task<Void, Never>?

    /// Active ou désactive la session audio hors du fil principal (AVAudioSession peut bloquer),
    /// mais strictement dans l'ordre des demandes. Auparavant, deux `Task.detached` indépendantes
    /// (désactivation dans `stop()`, puis activation pour le titre suivant) pouvaient s'exécuter
    /// dans le désordre et laisser la session désactivée pendant la lecture.
    private func enqueueAudioSessionChange(active: Bool) {
        let previous = audioSessionTask
        audioSessionTask = Task.detached(priority: .userInitiated) {
            await previous?.value
            do {
                let session = AVAudioSession.sharedInstance()
                if active {
                    try session.setCategory(.playback, mode: .default, options: [])
                    try session.setActive(true)
                } else {
                    try session.setActive(false, options: .notifyOthersOnDeactivation)
                }
            } catch {
                Logger(subsystem: AppInfo.logSubsystem, category: "AppleMusicPlayback")
                    .error("Configuration AVAudioSession (active=\(active)) échouée : \(error, privacy: .public)")
            }
        }
    }

    private func playFull(_ song: MusicKit.Song) async {
        await NowPlayingActivityManager.shared.endCurrentActivity()
        let player = ApplicationMusicPlayer.shared
        player.queue = [song]
        totalDuration = song.duration ?? 0
        playbackTime = 0

        do {
            try await player.play()
            startFullProgressPolling()
        } catch {
            logger.error("Lecture complète MusicKit échouée pour \(song.title, privacy: .private) : \(error, privacy: .public)")
            playPreview(song)
        }
    }

    /// Toutes les 0,5s plutôt que 10 fois par seconde : largement suffisant pour une barre de
    /// progression visuelle, et évite de marteler `ApplicationMusicPlayer` en boucle serrée — une
    /// cadence trop élevée a été observée comme déclenchant en rafale l'avertissement interne
    /// MediaPlayer "No catalogID, libraryID, or deviceLocalID..." (centaines de fois en quelques
    /// secondes), corrélé à des gels ponctuels de l'app. On s'arrête aussi dès que le lecteur n'a
    /// plus d'entrée valide en cours, plutôt que de continuer à interroger un état invalide.
    private func startFullProgressPolling() {
        progressPollingTask?.cancel()
        progressPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, self.isPlaying else { break }
                let player = ApplicationMusicPlayer.shared
                // Morceau terminé (ou lecteur vidé) : sans ce cas, le mini-lecteur restait affiché
                // "en lecture" indéfiniment après la fin du titre.
                guard player.queue.currentEntry != nil, player.state.playbackStatus != .stopped else {
                    self.stop()
                    break
                }
                self.playbackTime = player.playbackTime
            }
        }
    }

    private func song(
        trackID: String,
        artistName: String,
        albumTitle: String,
        trackTitle: String,
        trackDuration: String?,
        requestAuthorizationIfNeeded: Bool
    ) async -> MusicKit.Song? {
        let key = "\(artistName)|\(albumTitle)|\(trackTitle)".lowercased()
        // `songCache[key]` est un `Song??` : `.some(nil)` = recherche déjà faite, sans correspondance.
        if let cached = songCache[key] {
            matchStatusByTrackID[trackID] = cached != nil
            return cached
        }

        // Attend l'autorisation avant de chercher plutôt qu'en course avec elle : sans ça, le
        // tout premier appel MusicKit d'une session déclenche à la fois la recherche et l'invite
        // système, et la recherche échoue avant que l'utilisateur n'ait pu répondre à l'invite.
        // Lors d'un simple préchargement passif (page qui s'affiche), on ne demande jamais
        // l'invite — seul un vrai appui sur le bouton (`requestAuthorizationIfNeeded == true`) le
        // fait ; en attendant, le statut reste `nil` (inconnu) plutôt que `false` (pas de
        // correspondance), pour que le bouton redonne sa chance à la recherche au prochain appui.
        let isAuthorized = requestAuthorizationIfNeeded
            ? await AppleMusicAccountStore.shared.ensureAuthorizationRequested()
            : AppleMusicAccountStore.shared.isAuthorized
        guard isAuthorized else {
            if requestAuthorizationIfNeeded {
                matchStatusByTrackID[trackID] = false
            }
            return nil
        }
        do {
            var request = MusicCatalogSearchRequest(term: "\(artistName) \(trackTitle)", types: [MusicKit.Song.self])
            request.limit = 10
            let response = try await request.response()
            let match = bestMatch(
                in: response.songs,
                artistName: artistName,
                albumTitle: albumTitle,
                trackTitle: trackTitle,
                trackDuration: Self.parseDiscogsDuration(trackDuration)
            )
            // `updateValue` : sur un dictionnaire à valeurs optionnelles, `songCache[key] = match`
            // avec `match == nil` SUPPRIME la clé au lieu de mémoriser "aucune correspondance".
            songCache.updateValue(match, forKey: key)
            matchStatusByTrackID[trackID] = match != nil
            return match
        } catch {
            // Erreur de recherche (réseau, service MusicKit…) : rien n'est mémorisé et le statut
            // reste inconnu, pour qu'un prochain appui retente. Auparavant, le titre était marqué
            // "sans correspondance" et son bouton restait grisé pour toute la session.
            logger.error("Recherche MusicKit échouée pour \(trackTitle, privacy: .private) : \(error, privacy: .public)")
            return nil
        }
    }

    // MARK: - Correspondance par score de similarité

    /// Seuils en dessous desquels on préfère n'avoir aucune correspondance plutôt que de jouer le
    /// mauvais morceau en silence — contrairement à un simple `.first`, un score trop faible ne
    /// "devine" jamais : le bouton reste grisé.
    private static let minimumTitleScore = 0.6
    private static let minimumArtistScore = 0.5

    /// Sélectionne, parmi les résultats de recherche, celui dont le titre ET l'artiste se
    /// rapprochent le plus du titre Discogs — plutôt que de prendre le premier résultat dont
    /// l'artiste contient vaguement le nom recherché (ce qui pouvait faire jouer un morceau
    /// homonyme sans rapport). L'album sert de simple bonus de départage, jamais de filtre
    /// strict : les titres d'édition Discogs et Apple Music divergent trop souvent (réédition,
    /// compilation, intitulé régional) pour l'exiger.
    private func bestMatch(
        in candidates: MusicItemCollection<MusicKit.Song>,
        artistName: String,
        albumTitle: String,
        trackTitle: String,
        trackDuration: TimeInterval?
    ) -> MusicKit.Song? {
        let normalizedArtist = Self.normalize(artistName)
        let normalizedAlbum = Self.normalize(albumTitle)
        let normalizedTitle = Self.normalize(trackTitle)

        logger.debug("bestMatch pour « \(trackTitle, privacy: .private) » — \(candidates.count, privacy: .public) candidat(s) Apple Music reçu(s)")

        var best: (song: MusicKit.Song, score: Double)?
        for candidate in candidates {
            let titleScore = Self.similarity(Self.normalize(candidate.title), normalizedTitle)
            let artistScore = Self.artistSimilarity(Self.normalize(candidate.artistName), normalizedArtist)
            let passesThreshold = titleScore >= Self.minimumTitleScore && artistScore >= Self.minimumArtistScore
            let albumBonus = Self.normalize(candidate.albumTitle ?? "") == normalizedAlbum ? 0.1 : 0.0
            let durationAdjustment = Self.durationAdjustment(discogsDuration: trackDuration, candidateDuration: candidate.duration)
            let combinedScore = titleScore * 0.6 + artistScore * 0.3 + albumBonus + durationAdjustment

            logger.debug("  candidat « \(candidate.title, privacy: .private) » — \(candidate.artistName, privacy: .private) — album « \(candidate.albumTitle ?? "?", privacy: .private) » — durée \(candidate.duration ?? -1, privacy: .public)s — titleScore=\(titleScore, privacy: .public) artistScore=\(artistScore, privacy: .public) albumBonus=\(albumBonus, privacy: .public) durationAdj=\(durationAdjustment, privacy: .public) combined=\(combinedScore, privacy: .public) seuilOK=\(passesThreshold, privacy: .public)")

            guard passesThreshold else { continue }
            if best == nil || combinedScore > best!.score {
                best = (candidate, combinedScore)
            }
        }
        if best == nil {
            logger.debug("bestMatch pour « \(trackTitle, privacy: .private) » — aucun candidat au-dessus du seuil (titre≥\(Self.minimumTitleScore, privacy: .public), artiste≥\(Self.minimumArtistScore, privacy: .public))")
        }
        return best?.song
    }

    /// Bonus si la durée Apple Music est proche de celle renseignée sur Discogs, malus si elle
    /// s'en écarte nettement (signe probable d'un live/remix/radio edit plutôt que l'originale) —
    /// jamais un filtre strict : les durées Discogs sont saisies à la main et parfois absentes ou
    /// imprécises, contrairement au titre/artiste qui restent le critère principal.
    private static func durationAdjustment(discogsDuration: TimeInterval?, candidateDuration: TimeInterval?) -> Double {
        guard let discogsDuration, let candidateDuration, discogsDuration > 0 else { return 0 }
        let difference = abs(discogsDuration - candidateDuration)
        switch difference {
        case ..<5: return 0.15
        case ..<15: return 0.05
        case ..<30: return -0.1
        default: return -0.25
        }
    }

    /// Lit une durée au format Discogs (`"3:45"`) en secondes, `nil` si absente ou invalide.
    private static func parseDiscogsDuration(_ duration: String?) -> TimeInterval? {
        guard let seconds = duration?.discogsDurationSeconds else { return nil }
        return TimeInterval(seconds)
    }

    /// Nettoie un titre/nom pour la comparaison : retire le bruit entre parenthèses/crochets
    /// (`feat.`, `Remastered 2011`, `Live`, `Remix`...), les diacritiques et la ponctuation, pour
    /// que deux variantes d'écriture du même titre se comparent correctement.
    private static func normalize(_ string: String) -> String {
        var result = string
        while let openRange = result.range(of: "("), let closeRange = result.range(of: ")", range: openRange.upperBound..<result.endIndex) {
            result.removeSubrange(openRange.lowerBound...closeRange.lowerBound)
        }
        while let openRange = result.range(of: "["), let closeRange = result.range(of: "]", range: openRange.upperBound..<result.endIndex) {
            result.removeSubrange(openRange.lowerBound...closeRange.lowerBound)
        }
        result = result.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        result = result.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: " ")
        return result.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Similarité spécifique aux noms d'artiste : un featuring Apple Music ("Daft Punk & Julian
    /// Casablancas") ne doit pas être pénalisé par la différence de longueur face à l'artiste
    /// principal Discogs ("Daft Punk") — si tous les mots de l'un se retrouvent dans l'autre,
    /// c'est traité comme une forte correspondance plutôt que via la distance de Levenshtein
    /// brute, qui sous-évalue ce cas très fréquent. Les deux chaînes sont supposées déjà
    /// normalisées (voir `normalize`).
    private static func artistSimilarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let wordsA = Set(a.split(separator: " "))
        let wordsB = Set(b.split(separator: " "))
        if !wordsA.isEmpty, !wordsB.isEmpty, wordsA.isSubset(of: wordsB) || wordsB.isSubset(of: wordsA) {
            return 0.9
        }
        return similarity(a, b)
    }

    /// Ratio de similarité entre 0 (complètement différents) et 1 (identiques), basé sur la
    /// distance de Levenshtein normalisée par la longueur de la plus longue chaîne.
    private static func similarity(_ a: String, _ b: String) -> Double {
        if a.isEmpty && b.isEmpty { return 1 }
        let maxLength = max(a.count, b.count)
        guard maxLength > 0 else { return 1 }
        return 1 - Double(levenshteinDistance(a, b)) / Double(maxLength)
    }

    private static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previousRow = Array(0...b.count)
        var currentRow = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            currentRow[0] = i
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    currentRow[j] = previousRow[j - 1]
                } else {
                    currentRow[j] = 1 + min(previousRow[j - 1], previousRow[j], currentRow[j - 1])
                }
            }
            previousRow = currentRow
        }
        return previousRow[b.count]
    }
}
