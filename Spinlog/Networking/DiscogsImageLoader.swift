import Foundation

/// Charge les images Discogs (pochettes, photos de release...) en respectant les mêmes
/// contraintes que le reste de l'API : header `User-Agent` obligatoire et signature OAuth 1.0a,
/// avec un cache mémoire dont chaque entrée expire après 6h (pas de miroir permanent des
/// données Discogs, conformément aux CGU). Les URLs d'images renvoyées par l'API sont déjà
/// signées et éphémères côté Discogs : on les utilise telles quelles, sans jamais les reconstruire.
actor DiscogsImageLoader {
    static let shared = DiscogsImageLoader()

    private struct CacheEntry {
        let data: Data
        let cachedAt: Date
    }

    private let cacheLifetime: TimeInterval = 6 * 60 * 60
    private var cache: [URL: CacheEntry] = [:]
    private let session = URLSession.shared
    private let signer = OAuth1Signer(
        consumerKey: DiscogsSecrets.consumerKey,
        consumerSecret: DiscogsSecrets.consumerSecret
    )

    func loadData(from url: URL, credentials: DiscogsCredentials?) async throws -> Data {
        if let entry = cache[url], Date().timeIntervalSince(entry.cachedAt) < cacheLifetime {
            return entry.data
        }

        var request = URLRequest(url: url)
        request.setValue(DiscogsSecrets.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            signer.authorizationHeader(
                method: "GET",
                url: url,
                token: credentials?.token,
                tokenSecret: credentials?.tokenSecret ?? ""
            ),
            forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        cache[url] = CacheEntry(data: data, cachedAt: Date())
        return data
    }
}
