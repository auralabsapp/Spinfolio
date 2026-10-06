import Foundation
import UIKit
import Kingfisher

@MainActor
enum KingfisherConfig {
    /// Configure Kingfisher pour le chargement et la mise en cache des pochettes d'albums.
    /// Pour supporter le Mode Hors Ligne sans perte de jaquettes sans réseau, le stockage
    /// disque est conservé sur 30 jours (ou jusqu'à vidage manuel du cache), tandis que le
    /// cache mémoire utilise la fenêtre de 6 heures.
    static func configure() {
        let cache = ImageCache.default

        // Répértoire Library/Caches : 30 jours de persistance pour consultation hors ligne
        cache.diskStorage.config.expiration = .days(30)
        cache.memoryStorage.config.expiration = .seconds(DiscogsConstants.sixHoursTTL)

        // Downloader : injection automatique des headers requis par Discogs
        let modifier = AnyModifier { request in
            var req = request
            req.setValue(DiscogsSecrets.userAgent, forHTTPHeaderField: "User-Agent")

            if let url = req.url {
                let keychain = KeychainStore()
                let token = keychain.get("accessToken")
                let secret = keychain.get("accessTokenSecret")
                let signer = OAuth1Signer(
                    consumerKey: DiscogsSecrets.consumerKey,
                    consumerSecret: DiscogsSecrets.consumerSecret
                )
                let authHeader = signer.authorizationHeader(
                    method: req.httpMethod ?? "GET",
                    url: url,
                    token: token,
                    tokenSecret: secret ?? ""
                )
                req.setValue(authHeader, forHTTPHeaderField: "Authorization")
            }
            return req
        }

        KingfisherManager.shared.defaultOptions = [
            .requestModifier(modifier),
            .diskCacheExpiration(.days(30)),
            .memoryCacheExpiration(.seconds(DiscogsConstants.sixHoursTTL)),
            .cacheOriginalImage
        ]
    }

    /// Vide le cache disque de Kingfisher à la demande de l'utilisateur pour libérer de l'espace.
    static func clearDiskCache() {
        ImageCache.default.clearDiskCache()
        ImageCache.default.clearMemoryCache()
    }

    /// Calcule la taille occupée par le cache des images sur le disque.
    static func calculateDiskCacheSize() async -> String {
        await withCheckedContinuation { continuation in
            ImageCache.default.calculateDiskStorageSize { result in
                switch result {
                case .success(let size):
                    let formatter = ByteCountFormatter()
                    formatter.allowedUnits = [.useMB, .useGB]
                    formatter.countStyle = .file
                    continuation.resume(returning: formatter.string(fromByteCount: Int64(size)))
                case .failure:
                    continuation.resume(returning: "0 Mo")
                }
            }
        }
    }
}
