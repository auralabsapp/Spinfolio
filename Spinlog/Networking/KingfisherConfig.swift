import Foundation
import UIKit
import Kingfisher

@MainActor
enum KingfisherConfig {
    /// Configure Kingfisher pour le chargement et la mise en cache des pochettes d'albums
    /// avec une durée d'expiration maximale de 6 heures (21600s), stockage dans Library/Caches,
    /// et injection des headers User-Agent et Authorization OAuth Discogs.
    static func configure() {
        let cache = ImageCache.default

        // Répertoire Library/Caches avec expiration max de 6 heures (21600s)
        cache.diskStorage.config.expiration = .seconds(21600)
        cache.memoryStorage.config.expiration = .seconds(21600)

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
            .diskCacheExpiration(.seconds(21600)),
            .memoryCacheExpiration(.seconds(21600)),
            .cacheOriginalImage
        ]
    }
}
