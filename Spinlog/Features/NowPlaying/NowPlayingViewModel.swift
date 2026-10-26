import Foundation
import OSLog

private let nowPlayingLogger = Logger(subsystem: AppInfo.logSubsystem, category: "NowPlaying")

/// Charge l'album de la lecture en cours pour la fenêtre plein écran. Passe par
/// `DiscogsAPIClient` (cache, limiteur et mode démo compris), jamais depuis la vue.
@Observable
@MainActor
final class NowPlayingViewModel {
    private(set) var album: NowPlayingAlbum?
    private(set) var isLoading = false
    /// Album illisible (hors ligne, release introuvable) : la fenêtre garde l'en-tête du titre en
    /// cours et signale simplement que la liste des pistes est indisponible.
    private(set) var loadFailed = false

    private var loadedKey: String?

    /// `destination` : écran d'origine de la lecture (release ou master). Rien n'est rechargé si
    /// c'est déjà l'album affiché.
    func load(destination: SearchDestination?) async {
        let key: String
        switch destination {
        case .release(let id, _): key = "release-\(id)"
        case .master(let id): key = "master-\(id)"
        default:
            album = nil
            loadFailed = true
            return
        }
        guard key != loadedKey else { return }

        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        let credentials = DiscogsAuthManager.shared.credentials
        do {
            let loaded: NowPlayingAlbum
            switch destination {
            case .release(let id, _):
                loaded = NowPlayingAlbum(release: try await DiscogsAPIClient.shared.release(id: id, credentials: credentials))
            case .master(let id):
                loaded = NowPlayingAlbum(master: try await DiscogsAPIClient.shared.masterRelease(id: id, credentials: credentials))
            default:
                return
            }
            guard !Task.isCancelled else { return }
            album = loaded
            loadedKey = key
        } catch {
            guard !error.isCancellation else { return }
            nowPlayingLogger.error("Album de la lecture en cours illisible : \(error, privacy: .public)")
            album = nil
            loadFailed = true
        }
    }
}
