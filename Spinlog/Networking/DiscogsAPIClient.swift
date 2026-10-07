import Foundation

/// Identifiants d'accès Discogs pour une requête authentifiée (access token OAuth d'un utilisateur).
struct DiscogsCredentials: Sendable {
    let token: String
    let tokenSecret: String
}

extension Error {
    /// `true` si l'erreur provient de l'annulation de la tâche (attente du rate limiter ou requête
    /// réseau interrompue) : ce n'est pas un échec à montrer à l'utilisateur, la tâche a
    /// simplement été remplacée (nouvelle frappe, changement de dossier ou de tri...).
    var isCancellation: Bool {
        self is CancellationError || (self as? URLError)?.code == .cancelled
    }

    /// `true` si un nouvel essai a une chance d'aboutir : réseau indisponible ou interrompu,
    /// quota Discogs dépassé, erreur serveur (5xx). Les autres erreurs (4xx : identifiants
    /// invalides, release inexistante, requête refusée…) se reproduiront à l'identique.
    var isTransientNetworkFailure: Bool {
        if self is URLError || isCancellation { return true }
        guard let apiError = self as? DiscogsAPIClient.APIError else { return false }
        switch apiError {
        case .rateLimited: return true
        case .http(let status, _): return status == 429 || status >= 500
        case .invalidURL, .invalidResponse: return false
        }
    }

    /// `true` pour un 404 Discogs : pour une suppression, la ressource est déjà absente — le but
    /// de la requête est donc atteint.
    var isNotFound: Bool {
        if let apiError = self as? DiscogsAPIClient.APIError, case .http(404, _) = apiError { return true }
        return false
    }
}

/// Client HTTP générique pour l'API REST Discogs (réponses JSON).
/// Le flux OAuth (request_token / access_token, réponses form-encoded) est géré séparément
/// par `DiscogsAuthManager`, qui réutilise le même `OAuth1Signer`.
/// Classe simple plutôt qu'`actor` : aucun état mutable partagé, et un `actor` entrerait en
/// conflit avec l'isolation `@MainActor` par défaut du projet pour `Secrets.swift`/les modèles.
/// Le débit est régulé séparément par `DiscogsRateLimiter` (60 requêtes/minute Discogs).
@MainActor
final class DiscogsAPIClient {
    static let shared = DiscogsAPIClient()

    enum APIError: LocalizedError {
        case invalidURL
        case invalidResponse
        case rateLimited
        case http(status: Int, message: String?)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "URL Discogs invalide."
            case .invalidResponse:
                return "Réponse Discogs invalide."
            case .rateLimited:
                return "Trop de requêtes vers Discogs, réessaie dans quelques instants."
            case .http(let status, let message):
                return message ?? "Erreur Discogs (\(status))."
            }
        }
    }

    private struct DiscogsErrorBody: Decodable { let message: String? }

    private let baseURL = URL(string: "https://api.discogs.com")!
    private let session = URLSession.shared
    private let signer = OAuth1Signer(
        consumerKey: DiscogsSecrets.consumerKey,
        consumerSecret: DiscogsSecrets.consumerSecret
    )
    private let decoder = JSONDecoder()
    private let rateLimiter = DiscogsRateLimiter.shared

    /// Effectue une requête JSON vers l'API Discogs, signée en OAuth 1.0a.
    /// - Parameter credentials: identifiants de l'utilisateur connecté ; `nil` pour un accès public
    ///   (signé avec la seule clé de l'app, suffisant pour la recherche du catalogue).
    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        credentials: DiscogsCredentials? = nil
    ) async throws -> T {
        let (data, _) = try await perform(path: path, method: method, queryItems: queryItems, body: body, credentials: credentials)
        return try decoder.decode(T.self, from: data)
    }

    /// Requête sans corps de réponse exploitable (ex: DELETE qui renvoie 204/200 vide).
    @discardableResult
    func requestVoid(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        credentials: DiscogsCredentials?
    ) async throws -> Bool {
        _ = try await perform(path: path, method: method, queryItems: queryItems, body: body, credentials: credentials)
        return true
    }

    /// Construit, régule (throttle) et envoie la requête signée ; réessaie une fois en cas de 429
    /// en respectant `Retry-After`, conformément au quota Discogs (60 req/min, header `X-Discogs-Ratelimit*`).
    private func perform(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: Data? = nil,
        credentials: DiscogsCredentials?
    ) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue(DiscogsSecrets.userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for attempt in 0...2 {
            try await rateLimiter.waitForSlot()

            // Signé à chaque tentative, juste avant l'envoi : un retry après 429 repart plusieurs
            // secondes plus tard, et réutiliser le même `oauth_nonce`/`oauth_timestamp` peut être
            // rejeté par Discogs comme un rejeu.
            urlRequest.setValue(
                signer.authorizationHeader(
                    method: method,
                    url: url,
                    token: credentials?.token,
                    tokenSecret: credentials?.tokenSecret ?? ""
                ),
                forHTTPHeaderField: "Authorization"
            )

            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            await rateLimiter.recordResponse(http)

            if http.statusCode == 429, attempt < 2 {
                let delay = await rateLimiter.retryDelay(after: http)
                // `try` (et non `try?`) : une tâche annulée pendant l'attente (changement de
                // dossier, de compte...) ne doit pas renvoyer sa requête.
                try await Task.sleep(for: .seconds(delay))
                continue
            }

            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 429 {
                    throw APIError.rateLimited
                }
                let body = try? decoder.decode(DiscogsErrorBody.self, from: data)
                throw APIError.http(status: http.statusCode, message: body?.message)
            }

            return (data, http)
        }
        throw APIError.rateLimited
    }
}
