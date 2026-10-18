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
        case .invalidURL, .invalidResponse, .demoReadOnly: return false
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
        /// Modification du compte refusée en mode démo (voir `DemoMode`).
        case demoReadOnly

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return String(localized: "URL Discogs invalide.")
            case .invalidResponse:
                return String(localized: "Réponse Discogs invalide.")
            case .rateLimited:
                return String(localized: "Trop de requêtes vers Discogs, réessaie dans quelques instants.")
            case .http(let status, let message):
                return message ?? String(localized: "Erreur Discogs (\(String(status))).")
            case .demoReadOnly:
                return AppMessages.demoModificationBlocked
            }
        }
    }

    private struct DiscogsErrorBody: Decodable { let message: String? }

    private let baseURL = DiscogsConstants.apiBaseURL
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

    /// Comme `request`, mais décode la réponse hors du fil principal : pour les réponses
    /// volumineuses reçues en série (classement des discographies), dont le décodage répété
    /// pourrait saccader l'interface. `T` doit être déclaré `nonisolated` (décodable hors de
    /// l'acteur principal).
    func requestDecodingInBackground<T: Decodable & Sendable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        credentials: DiscogsCredentials? = nil
    ) async throws -> T {
        let (data, _) = try await perform(path: path, method: "GET", queryItems: queryItems, credentials: credentials)
        return try await Task.detached(priority: .utility) {
            try JSONDecoder().decode(T.self, from: data)
        }.value
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
        var credentials = credentials
        if DemoMode.isActive {
            if let data = try DemoServer.response(path: path, method: method, queryItems: queryItems) {
                let url = baseURL.appendingPathComponent(path)
                guard let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
                    throw APIError.invalidResponse
                }
                return (data, http)
            }
            // Requête publique (catalogue) : les identifiants fictifs de la démo seraient
            // refusés par Discogs, la clé de l'app suffit.
            credentials = nil
        }
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
            try await rateLimiter.waitForSlot(priority: DiscogsRateLimiter.priority)

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
