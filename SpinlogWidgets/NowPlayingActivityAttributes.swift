import Foundation
import ActivityKit

/// Attributs partagés de la Live Activity et de la Dynamic Island pour Spinlog.
/// `nonisolated` explicite : le module par défaut isole tout au MainActor, mais ActivityKit
/// doit pouvoir utiliser ce type depuis un contexte concurrent hors MainActor (mise à jour/fin
/// d'activité), d'où l'avertissement Swift 6 sans cette annotation.
public nonisolated struct NowPlayingActivityAttributes: ActivityAttributes {
    public nonisolated struct ContentState: Codable, Hashable {
        /// Date de démarrage de la session d'écoute
        public var startedAt: Date
        /// Ancien statut textuel, plus affiché : la Live Activity affiche désormais un libellé
        /// localisé par l'extension. Conservé pour décoder les activités démarrées par une
        /// version antérieure de l'app.
        public var statusText: String
        /// Données binaires d'image de la jaquette redimensionnée (JPEG compact < 50 Ko pour respecter la limite ActivityKit de 4 Ko - 100 Ko)
        public var coverImageData: Data?

        public init(startedAt: Date = Date(), statusText: String = "", coverImageData: Data? = nil) {
            self.startedAt = startedAt
            self.statusText = statusText
            self.coverImageData = coverImageData
        }
    }

    /// ID de la release Discogs
    public var releaseId: Int
    /// Titre de l'album
    public var albumTitle: String
    /// Nom de l'artiste
    public var artistName: String

    /// Jeton aléatoire propre à cette écoute, joint au lien « Arrêter » (`endSessionURL`) : sans
    /// lui, n'importe quelle page ou app pouvait ouvrir `spinlog://end-session` et couper
    /// l'écoute. `nil` pour une activité démarrée par une version antérieure de l'app.
    public var sessionToken: String?

    public init(releaseId: Int, albumTitle: String, artistName: String, sessionToken: String? = nil) {
        self.releaseId = releaseId
        self.albumTitle = albumTitle
        self.artistName = artistName
        self.sessionToken = sessionToken
    }

    /// Lien du bouton « Arrêter » de la Live Activity.
    public var endSessionURL: URL? {
        var components = URLComponents()
        components.scheme = "spinlog"
        components.host = "end-session"
        components.path = "/\(releaseId)"
        if let sessionToken {
            components.queryItems = [URLQueryItem(name: "token", value: sessionToken)]
        }
        return components.url
    }

    /// Demande d'arrêt lue dans un lien `spinlog://end-session/{releaseId}?token=…`.
    public static func endSessionRequest(from url: URL) -> (releaseId: Int, token: String?)? {
        guard url.scheme == "spinlog", url.host == "end-session",
              let releaseId = Int(url.path.replacingOccurrences(of: "/", with: "")) else { return nil }
        let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "token" }?.value
        return (releaseId, token)
    }

    /// Le lien vient bien du bouton de cette activité : même jeton (absent des deux côtés pour
    /// une activité d'avant le jeton).
    public func acceptsEndRequest(token: String?) -> Bool {
        sessionToken == token
    }
}
