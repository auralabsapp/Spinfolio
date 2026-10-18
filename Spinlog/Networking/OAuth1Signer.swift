import Foundation
import CryptoKit

/// Signe les requêtes selon OAuth 1.0a (HMAC-SHA1), tel qu'exigé par l'API Discogs.
/// Référence : https://www.discogs.com/developers#page:authentication
nonisolated struct OAuth1Signer: Sendable {
    let consumerKey: String
    let consumerSecret: String

    /// Construit l'en-tête `Authorization: OAuth ...` pour une requête donnée.
    /// - Parameters:
    ///   - token: le oauth_token (request token ou access token). `nil` pour une requête non authentifiée.
    ///   - tokenSecret: le secret associé au token ci-dessus.
    ///   - additionalParameters: paramètres OAuth supplémentaires à signer (ex: oauth_callback, oauth_verifier).
    ///   - nonce, timestamp: aléatoire et heure courante ; injectables pour vérifier la signature
    ///     sur un exemple de référence dans les tests.
    func authorizationHeader(
        method: String,
        url: URL,
        token: String? = nil,
        tokenSecret: String = "",
        additionalParameters: [String: String] = [:],
        nonce: String = UUID().uuidString.replacingOccurrences(of: "-", with: ""),
        timestamp: Date = Date()
    ) -> String {
        var oauthParameters: [String: String] = [
            "oauth_consumer_key": consumerKey,
            "oauth_nonce": nonce,
            "oauth_signature_method": "HMAC-SHA1",
            "oauth_timestamp": String(Int(timestamp.timeIntervalSince1970)),
            "oauth_version": "1.0"
        ]
        if let token {
            oauthParameters["oauth_token"] = token
        }
        for (key, value) in additionalParameters {
            oauthParameters[key] = value
        }

        oauthParameters["oauth_signature"] = signature(
            method: method,
            url: url,
            oauthParameters: oauthParameters,
            tokenSecret: tokenSecret
        )

        let headerParameters = oauthParameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\"\(percentEncode($0.value))\"" }
            .joined(separator: ", ")
        return "OAuth \(headerParameters)"
    }

    private func signature(
        method: String,
        url: URL,
        oauthParameters: [String: String],
        tokenSecret: String
    ) -> String {
        var allParameters = oauthParameters
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems {
                allParameters[item.name] = item.value ?? ""
            }
        }

        let parameterString = allParameters
            .sorted { $0.key < $1.key }
            .map { "\(percentEncode($0.key))=\(percentEncode($0.value))" }
            .joined(separator: "&")

        let baseString = [
            method.uppercased(),
            percentEncode(urlWithoutQuery(url).absoluteString),
            percentEncode(parameterString)
        ].joined(separator: "&")

        let signingKey = "\(percentEncode(consumerSecret))&\(percentEncode(tokenSecret))"
        let key = SymmetricKey(data: Data(signingKey.utf8))
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(baseString.utf8), using: key)
        return Data(mac).base64EncodedString()
    }

    private func urlWithoutQuery(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        return components?.url ?? url
    }

    /// Encodage pourcentage strict RFC 3986, requis par la spec OAuth 1.0a
    /// (plus strict que `addingPercentEncoding` avec les character sets standard de Foundation).
    private func percentEncode(_ string: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
