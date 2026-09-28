import Foundation
import AuthenticationServices
import UIKit
import Observation

/// Orchestre le flow OAuth 1.0a "3-legged" de Discogs (request token → autorisation
/// navigateur → access token) et conserve les tokens obtenus dans le Keychain.
/// Référence : https://www.discogs.com/developers#page:authentication,header:authentication-oauth-flow
@Observable
@MainActor
final class DiscogsAuthManager: NSObject {
    static let shared = DiscogsAuthManager()

    private(set) var isAuthenticated: Bool
    private(set) var username: String?
    private(set) var isAuthenticating = false
    var lastError: String?

    private let keychain = KeychainStore()
    private let signer = OAuth1Signer(
        consumerKey: DiscogsSecrets.consumerKey,
        consumerSecret: DiscogsSecrets.consumerSecret
    )
    private let callbackURL = URL(string: "spinlog://oauth-callback")!
    private var webAuthSession: ASWebAuthenticationSession?

    var credentials: DiscogsCredentials? {
        guard let token = keychain.get(Keys.accessToken),
              let secret = keychain.get(Keys.accessTokenSecret) else { return nil }
        return DiscogsCredentials(token: token, tokenSecret: secret)
    }

    private enum Keys {
        static let accessToken = "accessToken"
        static let accessTokenSecret = "accessTokenSecret"
        static let username = "username"
    }

    private override init() {
        let keychain = KeychainStore()
        self.isAuthenticated = keychain.get(Keys.accessToken) != nil
        self.username = keychain.get(Keys.username)
        super.init()
    }

    func login() async {
        guard !DiscogsSecrets.consumerKey.isEmpty, !DiscogsSecrets.consumerSecret.isEmpty else {
            lastError = "Ajoute ton Consumer Key et Consumer Secret Discogs dans Secrets.swift (crée une app sur discogs.com/settings/developers) pour activer la connexion."
            return
        }
        guard !isAuthenticating else { return }
        isAuthenticating = true
        lastError = nil
        defer { isAuthenticating = false }

        do {
            let requestToken = try await fetchRequestToken()
            let verifier = try await authorize(requestToken: requestToken.token)
            let accessToken = try await fetchAccessToken(
                requestToken: requestToken.token,
                requestTokenSecret: requestToken.secret,
                verifier: verifier
            )

            keychain.set(accessToken.token, forKey: Keys.accessToken)
            keychain.set(accessToken.secret, forKey: Keys.accessTokenSecret)

            let identity: Identity = try await DiscogsAPIClient.shared.request(
                path: "oauth/identity",
                credentials: DiscogsCredentials(token: accessToken.token, tokenSecret: accessToken.secret)
            )
            keychain.set(identity.username, forKey: Keys.username)
            username = identity.username
            isAuthenticated = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func logout() {
        keychain.remove(Keys.accessToken)
        keychain.remove(Keys.accessTokenSecret)
        keychain.remove(Keys.username)
        isAuthenticated = false
        username = nil
    }

    // MARK: - Étapes OAuth (réponses form-encoded, pas JSON)

    private func fetchRequestToken() async throws -> (token: String, secret: String) {
        let url = URL(string: "https://api.discogs.com/oauth/request_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(DiscogsSecrets.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            signer.authorizationHeader(
                method: "GET",
                url: url,
                additionalParameters: ["oauth_callback": callbackURL.absoluteString]
            ),
            forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response)
        let params = Self.parseFormBody(data)
        guard let token = params["oauth_token"], let secret = params["oauth_token_secret"] else {
            throw AuthError.invalidResponse
        }
        return (token, secret)
    }

    private func authorize(requestToken: String) async throws -> String {
        var components = URLComponents(string: "https://www.discogs.com/oauth/authorize")!
        components.queryItems = [URLQueryItem(name: "oauth_token", value: requestToken)]
        guard let authorizeURL = components.url else { throw AuthError.invalidResponse }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: callbackURL.scheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL,
                      let verifier = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "oauth_verifier" })?.value else {
                    continuation.resume(throwing: AuthError.invalidResponse)
                    return
                }
                continuation.resume(returning: verifier)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            webAuthSession = session
            session.start()
        }
    }

    private func fetchAccessToken(
        requestToken: String,
        requestTokenSecret: String,
        verifier: String
    ) async throws -> (token: String, secret: String) {
        let url = URL(string: "https://api.discogs.com/oauth/access_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(DiscogsSecrets.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            signer.authorizationHeader(
                method: "POST",
                url: url,
                token: requestToken,
                tokenSecret: requestTokenSecret,
                additionalParameters: ["oauth_verifier": verifier]
            ),
            forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response)
        let params = Self.parseFormBody(data)
        guard let token = params["oauth_token"], let secret = params["oauth_token_secret"] else {
            throw AuthError.invalidResponse
        }
        return (token, secret)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.invalidResponse
        }
    }

    private static func parseFormBody(_ data: Data) -> [String: String] {
        guard let string = String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for pair in string.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            result[key] = value
        }
        return result
    }

    enum AuthError: LocalizedError {
        case invalidResponse
        var errorDescription: String? { "Impossible de se connecter à Discogs." }
    }
}

extension DiscogsAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
