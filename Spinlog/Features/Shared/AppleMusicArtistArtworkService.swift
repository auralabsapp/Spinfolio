import Foundation
import MusicKit
import OSLog

private let logger = Logger(subsystem: "com.auralabs.Spinlog", category: "AppleMusicArtistArtwork")

/// Récupère la photo d'un artiste depuis le catalogue Apple Music (MusicKit), pour l'afficher à
/// la place de l'icône micro générique dans le classement "Artistes les plus écoutés" des
/// Statistiques. Purement décoratif : en cas de refus de permission, d'absence de résultat ou
/// d'erreur réseau, l'appelant retombe silencieusement sur l'icône micro — jamais d'état d'erreur
/// visible pour une fonctionnalité de ce niveau.
@MainActor
final class AppleMusicArtistArtworkService {
    static let shared = AppleMusicArtistArtworkService()

    /// `nil` tant qu'aucune recherche n'a été faite pour ce nom ; évite de redemander la même
    /// pochette à chaque fois qu'une ligne de classement est réaffichée (changement d'onglet,
    /// scroll, bascule "Albums"/"Artistes").
    private var cache: [String: URL?] = [:]
    private var authorizationStatus: MusicAuthorization.Status?

    private init() {}

    func artworkURL(for artistName: String) async -> URL? {
        let key = artistName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] {
            return cached
        }

        guard await isAuthorized() else {
            cache[key] = nil
            return nil
        }

        do {
            // Qualifié explicitement : le modèle `Artist` de l'app (Discogs, `Models/Artist.swift`)
            // porte le même nom que `MusicKit.Artist` et masque ce dernier par défaut dans ce module.
            var request = MusicCatalogSearchRequest(term: artistName, types: [MusicKit.Artist.self])
            request.limit = 1
            let response = try await request.response()
            let url = response.artists.first?.artwork?.url(width: 160, height: 160)
            cache[key] = url
            return url
        } catch {
            logger.error("Recherche MusicKit échouée pour \(artistName, privacy: .public) : \(error, privacy: .public)")
            cache[key] = nil
            return nil
        }
    }

    /// Demande l'autorisation une seule fois par lancement d'app (pas à chaque ligne de
    /// classement) ; un refus est mémorisé pour ne plus jamais redéclencher l'invite système.
    private func isAuthorized() async -> Bool {
        if let authorizationStatus {
            return authorizationStatus == .authorized
        }
        let status: MusicAuthorization.Status
        switch MusicAuthorization.currentStatus {
        case .authorized, .denied, .restricted:
            status = MusicAuthorization.currentStatus
        case .notDetermined:
            status = await MusicAuthorization.request()
        @unknown default:
            status = MusicAuthorization.currentStatus
        }
        authorizationStatus = status
        return status == .authorized
    }
}
