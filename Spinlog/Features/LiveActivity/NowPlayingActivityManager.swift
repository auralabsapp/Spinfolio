import SwiftUI
import Foundation
import ActivityKit
import UIKit
import Observation
import Kingfisher
import OSLog

private let logger = Logger(subsystem: "com.aurelienscarpa.Spinlog", category: "LiveActivity")

public enum ListeningMaxDurationOption: Int, CaseIterable, Identifiable, Sendable {
    case thirtyMinutes = 1800
    case fortyFiveMinutes = 2700
    case oneHour = 3600
    case ninetyMinutes = 5400
    case twoHours = 7200

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .thirtyMinutes: return String(localized: "30 minutes (1 face)")
        case .fortyFiveMinutes: return String(localized: "45 minutes")
        case .oneHour: return String(localized: "1 heure (recommandé)")
        case .ninetyMinutes: return String(localized: "1 heure 30 (double vinyle)")
        case .twoHours: return String(localized: "2 heures")
        }
    }
}

/// Gestionnaire du cycle de vie de la Live Activity « écoute sur platine » (Dynamic Island & Lock Screen).
///
/// `@Observable` (comme les autres stores de l'app) plutôt qu'`ObservableObject` : les vues ne
/// sont réinvalidées que pour les propriétés qu'elles lisent réellement, au lieu de l'être
/// toutes à chaque `@Published` modifié.
@Observable
@MainActor
final class NowPlayingActivityManager {
    static let shared = NowPlayingActivityManager()

    public static let maxListeningDurationKey = "spinlog_max_listening_duration"
    public static let defaultDuration: TimeInterval = 3600 // 1 heure

    private(set) var activeReleaseId: Int?
    private(set) var activeAlbumTitle: String?
    private(set) var activeArtistName: String?
    private(set) var activeCoverURL: String?
    private(set) var activeStartedAt: Date?
    @ObservationIgnored private var currentActivity: Activity<NowPlayingActivityAttributes>?
    @ObservationIgnored private var autoStopTask: Task<Void, Never>?

    public var maxListeningDuration: TimeInterval {
        let val = UserDefaults.standard.double(forKey: Self.maxListeningDurationKey)
        return val > 0 ? val : Self.defaultDuration
    }

    private init() {
        // Restaure l'état si une activité système est déjà en cours au lancement
        if let first = Activity<NowPlayingActivityAttributes>.activities.first {
            let elapsed = Date().timeIntervalSince(first.content.state.startedAt)
            let maxDuration = maxListeningDuration
            if elapsed >= maxDuration {
                Task {
                    await endCurrentActivity()
                }
            } else {
                self.currentActivity = first
                self.activeReleaseId = first.attributes.releaseId
                self.activeAlbumTitle = first.attributes.albumTitle
                self.activeArtistName = first.attributes.artistName
                self.activeStartedAt = first.content.state.startedAt
                scheduleAutoStop(for: first.attributes.releaseId, remainingSeconds: maxDuration - elapsed)
            }
        }
    }

    /// Vrai si une Live Activity est actuellement en cours pour cette release spécifique.
    func isPlaying(releaseId: Int) -> Bool {
        return activeReleaseId == releaseId
    }

    /// Vrai si une Live Activity est actuellement en cours (n'importe quel album).
    var isAnyPlaying: Bool {
        activeReleaseId != nil
    }

    /// Démarre une nouvelle Live Activity pour l'album en cours d'écoute.
    /// Si une écoute était déjà en cours, elle est immédiatement arrêtée au profit de la nouvelle.
    func startActivity(
        releaseId: Int,
        albumTitle: String,
        artistName: String,
        coverURL: String?
    ) {
        // Annule tout compte à rebours d'arrêt auto en cours
        autoStopTask?.cancel()
        autoStopTask = nil

        // Arrête la lecture Apple Music en cours si nécessaire
        if AppleMusicPlaybackService.shared.isPlaying {
            AppleMusicPlaybackService.shared.stop()
        }

        let now = Date()
        let duration = maxListeningDuration

        // Bascule immédiatement l'identifiant et les métadonnées pour le mini lecteur
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            self.activeReleaseId = releaseId
            self.activeAlbumTitle = albumTitle
            self.activeArtistName = artistName
            self.activeCoverURL = coverURL
            self.activeStartedAt = now
        }

        // Programme l'arrêt automatique après la durée maximale
        scheduleAutoStop(for: releaseId, remainingSeconds: duration)

        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            logger.error("Live Activities are NOT enabled in system settings for Spinlog.")
            return
        }

        // 1. Tente d'extraire immédiatement l'image du cache Kingfisher (mémoire puis disque)
        var initialCoverData: Data? = nil
        if let coverURL {
            initialCoverData = fetchSyncCoverData(from: coverURL)
        }

        let attributes = NowPlayingActivityAttributes(
            releaseId: releaseId,
            albumTitle: albumTitle,
            artistName: artistName
        )

        let initialState = NowPlayingActivityAttributes.ContentState(
            startedAt: now,
            coverImageData: initialCoverData
        )

        var newActivity: Activity<NowPlayingActivityAttributes>?
        do {
            let staleDate = now.addingTimeInterval(duration)
            let activity = try Activity<NowPlayingActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: staleDate),
                pushType: nil
            )
            self.currentActivity = activity
            newActivity = activity
            logger.info("Live Activity successfully started synchronously for release \(releaseId)")
        } catch {
            logger.error("Failed to request Live Activity: \(error.localizedDescription)")
        }

        // 2. Nettoyage asynchrone des anciennes activités et chargement de jaquette si absent du cache
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "SetupSpinlogLiveActivity") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }

        Task {
            // Ferme les anciennes activités différentes de celle créée
            for act in Activity<NowPlayingActivityAttributes>.activities where act.id != newActivity?.id {
                await act.end(nil, dismissalPolicy: .immediate)
            }

            // Si la jaquette n'était pas encore en cache, on la télécharge et met à jour l'activité
            if initialCoverData == nil, let activity = newActivity, let coverURL {
                if let coverData = await fetchAsyncCoverData(from: coverURL) {
                    let updatedState = NowPlayingActivityAttributes.ContentState(
                        startedAt: now,
                        coverImageData: coverData
                    )
                    await activity.update(.init(state: updatedState, staleDate: now.addingTimeInterval(duration)))
                    logger.info("Live Activity updated with async cover image for release \(releaseId)")
                }
            }

            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }
    }

    private func scheduleAutoStop(for releaseId: Int, remainingSeconds: TimeInterval) {
        autoStopTask?.cancel()
        guard remainingSeconds > 0 else {
            Task { await endCurrentActivity() }
            return
        }
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remainingSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self = self, self.activeReleaseId == releaseId else { return }
            logger.info("Durée max d'écoute atteinte pour release \(releaseId), arrêt automatique.")
            await self.endCurrentActivity()
        }
    }

    /// Vérifie si l'activité en cours a dépassé la durée maximale (utile au retour au premier plan)
    func checkExpiry() async {
        let maxDuration = maxListeningDuration
        for act in Activity<NowPlayingActivityAttributes>.activities {
            let elapsed = Date().timeIntervalSince(act.content.state.startedAt)
            if elapsed >= maxDuration {
                await act.end(nil, dismissalPolicy: .immediate)
            }
        }
        if let startedAt = activeStartedAt {
            let elapsed = Date().timeIntervalSince(startedAt)
            if elapsed >= maxDuration {
                await endCurrentActivity()
            }
        }
    }

    /// Vérifie le cache Kingfisher (mémoire puis disque) de manière synchrone et instantanée.
    private func fetchSyncCoverData(from coverURLString: String) -> Data? {
        guard let url = URL(string: coverURLString) else { return nil }
        if let memoryImage = ImageCache.default.retrieveImageInMemoryCache(forKey: url.cacheKey) {
            return resizeAndCompress(image: memoryImage)
        }
        if let data = try? ImageCache.default.diskStorage.value(forKey: url.cacheKey) {
            if let img = UIImage(data: data) {
                return resizeAndCompress(image: img)
            }
        }
        return nil
    }

    /// Récupère l'image depuis le cache ou télécharge via Discogs.
    private func fetchAsyncCoverData(from coverURLString: String) async -> Data? {
        guard let url = URL(string: coverURLString) else { return nil }

        let image: UIImage? = await withCheckedContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: url) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value.image)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }

        guard let image else { return nil }
        return resizeAndCompress(image: image)
    }

    /// Redimensionne l'image (72x72 px) et compresse pour garantir un payload compact (< 3.5 Ko)
    private func resizeAndCompress(image: UIImage) -> Data? {
        let targetSize = CGSize(width: 72, height: 72)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // 1x strict pour rester à 72x72 pixels
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard var data = resizedImage.jpegData(compressionQuality: 0.5) else { return nil }
        if data.count > 3500 {
            if let compressed = resizedImage.jpegData(compressionQuality: 0.3) {
                data = compressed
            }
        }
        return data
    }

    /// Ferme toutes les activités système sans modifier activeReleaseId
    private func endAllSystemActivities() async {
        if let activity = currentActivity {
            await activity.end(nil, dismissalPolicy: .immediate)
            self.currentActivity = nil
        }
        for act in Activity<NowPlayingActivityAttributes>.activities {
            await act.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Termine l'activité en cours d'écoute (lors de l'appui sur "Stop" ou "Annuler" ou expiration).
    func endCurrentActivity() async {
        autoStopTask?.cancel()
        autoStopTask = nil
        await endAllSystemActivities()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            self.activeReleaseId = nil
            self.activeAlbumTitle = nil
            self.activeArtistName = nil
            self.activeCoverURL = nil
            self.activeStartedAt = nil
        }
    }

    /// Termine une activité spécifique par son releaseId si elle correspond à celle en cours.
    func endActivity(for releaseId: Int) async {
        for act in Activity<NowPlayingActivityAttributes>.activities where act.attributes.releaseId == releaseId {
            await act.end(nil, dismissalPolicy: .immediate)
        }
        if activeReleaseId == releaseId {
            autoStopTask?.cancel()
            autoStopTask = nil
            currentActivity = nil
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                self.activeReleaseId = nil
                self.activeAlbumTitle = nil
                self.activeArtistName = nil
                self.activeCoverURL = nil
                self.activeStartedAt = nil
            }
        }
    }
}
