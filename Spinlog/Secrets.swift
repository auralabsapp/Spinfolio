import Foundation

/// Identifiants de l'application Discogs (à créer sur https://www.discogs.com/settings/developers).
/// Ce fichier est ignoré par git : chacun renseigne ses propres identifiants en local.
enum DiscogsSecrets {
    static let consumerKey = ""
    static let consumerSecret = ""

    /// Discogs exige un User-Agent descriptif sur chaque requête.
    static let userAgent = "Spinlog/1.0 +https://github.com/aurelienscarpa/Spinlog"
}
