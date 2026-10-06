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
        /// Éventuel statut textuel (par exemple: "En cours d'écoute")
        public var statusText: String
        /// Données binaires d'image de la jaquette redimensionnée (JPEG compact < 50 Ko pour respecter la limite ActivityKit de 4 Ko - 100 Ko)
        public var coverImageData: Data?

        public init(startedAt: Date = Date(), statusText: String = "En cours sur votre platine", coverImageData: Data? = nil) {
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

    public init(releaseId: Int, albumTitle: String, artistName: String) {
        self.releaseId = releaseId
        self.albumTitle = albumTitle
        self.artistName = artistName
    }
}
