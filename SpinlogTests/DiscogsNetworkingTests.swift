import Foundation
import Testing
@testable import Spinlog

/// Signature OAuth 1.0a : une erreur ici fait refuser toutes les requêtes Discogs du compte.
struct OAuth1SignerTests {
    /// Exemple de référence de la spécification OAuth 1.0 (annexe A.5) : HMAC-SHA1 sur une requête
    /// GET avec paramètres de requête, jeton et secrets connus.
    @Test func matchesTheOAuthSpecificationExample() throws {
        let signer = OAuth1Signer(consumerKey: "dpf43f3p2l4k3l03", consumerSecret: "kd94hf93k423kf44")
        let url = try #require(URL(string: "http://photos.example.net/photos?file=vacation.jpg&size=original"))

        let header = signer.authorizationHeader(
            method: "GET",
            url: url,
            token: "nnch734d00sl2jdk",
            tokenSecret: "pfkkdhi9sl3r4s00",
            nonce: "kllo9940pd9333jh",
            timestamp: Date(timeIntervalSince1970: 1_191_242_096)
        )

        #expect(header.hasPrefix("OAuth "))
        #expect(header.contains("oauth_signature=\"tR3%2BTy81lMeYAr%2FFid0kMTYa%2FWM%3D\""))
        #expect(header.contains("oauth_token=\"nnch734d00sl2jdk\""))
        // Les paramètres de requête sont signés mais ne vont pas dans l'en-tête.
        #expect(!header.contains("file="))
    }

    @Test func additionalParametersAreSignedAndPercentEncoded() throws {
        let signer = OAuth1Signer(consumerKey: "key", consumerSecret: "secret")
        let url = try #require(URL(string: "https://api.discogs.com/oauth/request_token"))
        let fixed = (nonce: "abc", timestamp: Date(timeIntervalSince1970: 1_700_000_000))

        let withCallback = signer.authorizationHeader(
            method: "GET", url: url,
            additionalParameters: ["oauth_callback": "spinlog://oauth-callback"],
            nonce: fixed.nonce, timestamp: fixed.timestamp
        )
        let withoutCallback = signer.authorizationHeader(
            method: "GET", url: url, nonce: fixed.nonce, timestamp: fixed.timestamp
        )

        // Encodage RFC 3986 strict : « : » et « / » sont encodés.
        #expect(withCallback.contains("oauth_callback=\"spinlog%3A%2F%2Foauth-callback\""))
        // Un paramètre supplémentaire change la signature.
        #expect(signatureValue(in: withCallback) != signatureValue(in: withoutCallback))
    }

    @Test func sameInputsGiveTheSameSignature() throws {
        let signer = OAuth1Signer(consumerKey: "key", consumerSecret: "secret")
        let url = try #require(URL(string: "https://api.discogs.com/users/alice/wants?page=2"))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = signer.authorizationHeader(method: "get", url: url, token: "t", tokenSecret: "s", nonce: "n", timestamp: date)
        let second = signer.authorizationHeader(method: "GET", url: url, token: "t", tokenSecret: "s", nonce: "n", timestamp: date)
        #expect(first == second)
    }

    private func signatureValue(in header: String) -> Substring? {
        guard let range = header.range(of: "oauth_signature=\"") else { return nil }
        let rest = header[range.upperBound...]
        return rest.split(separator: "\"").first
    }
}

/// Retour de la page d'autorisation Discogs : seul le retour de la demande en cours est accepté.
struct OAuthCallbackTests {
    @Test func verifierIsReadWhenTheTokenMatches() {
        let url = URL(string: "spinlog://oauth-callback?oauth_token=req123&oauth_verifier=ver456")
        #expect(DiscogsAuthManager.verifier(fromCallback: url, requestToken: "req123") == "ver456")
    }

    @Test(arguments: [
        "spinlog://oauth-callback?oauth_token=other&oauth_verifier=ver456",
        "spinlog://oauth-callback?oauth_verifier=ver456",
        "spinlog://oauth-callback?oauth_token=req123",
        "spinlog://oauth-callback?oauth_token=req123&oauth_verifier="
    ])
    func callbackIsRejected(_ raw: String) {
        #expect(DiscogsAuthManager.verifier(fromCallback: URL(string: raw), requestToken: "req123") == nil)
    }
}

/// Quota Discogs (60 requêtes/min) : calcul des créneaux, sans attente réelle.
struct DiscogsRateLimiterTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func requestGoesImmediatelyWhenQuotaIsFree() {
        let result = DiscogsRateLimiter.nextSlot(now: now, reservedSlots: [], remaining: nil)
        #expect(result.slot == now)
        #expect(result.remaining == nil)
    }

    @Test func fullRollingWindowWaitsForTheOldestRequestToExpire() {
        // 50 requêtes réparties sur la dernière minute, la plus ancienne il y a 59 s.
        let reserved = (0..<50).map { now.addingTimeInterval(-59 + Double($0)) }
        let result = DiscogsRateLimiter.nextSlot(now: now, reservedSlots: reserved, remaining: nil)
        #expect(result.slot == now.addingTimeInterval(1.5))
    }

    @Test func waitIsCappedAtTwentySeconds() {
        let reserved = Array(repeating: now, count: 50)
        let result = DiscogsRateLimiter.nextSlot(now: now, reservedSlots: reserved, remaining: nil)
        #expect(result.slot == now.addingTimeInterval(20))
    }

    @Test func lowDiscogsBalanceSpacesRequestsAndCountsDown() {
        let last = now.addingTimeInterval(-1)
        let low = DiscogsRateLimiter.nextSlot(now: now, reservedSlots: [last], remaining: 3)
        #expect(low.slot == last.addingTimeInterval(2))
        #expect(low.remaining == 2)

        let critical = DiscogsRateLimiter.nextSlot(now: now, reservedSlots: [last], remaining: 1)
        #expect(critical.slot == last.addingTimeInterval(10))
        #expect(critical.remaining == 0)

        let comfortable = DiscogsRateLimiter.nextSlot(now: now, reservedSlots: [last], remaining: 40)
        #expect(comfortable.slot == now)
        #expect(comfortable.remaining == 40)
    }

    @Test func backgroundRequestWaitsForAQuietPeriod() {
        let ready = DiscogsRateLimiter.backgroundReadyDate(
            now: now, lastNormalRequest: now.addingTimeInterval(-2), lastBackgroundSlot: nil,
            recentRequests: [], remaining: nil
        )
        #expect(ready == now.addingTimeInterval(6))
    }

    @Test func backgroundRequestsAreSpacedAndYieldOnLowBalance() {
        let spaced = DiscogsRateLimiter.backgroundReadyDate(
            now: now, lastNormalRequest: nil, lastBackgroundSlot: now.addingTimeInterval(-1),
            recentRequests: [], remaining: nil
        )
        #expect(spaced == now.addingTimeInterval(2))

        let lowBalance = DiscogsRateLimiter.backgroundReadyDate(
            now: now, lastNormalRequest: nil, lastBackgroundSlot: nil, recentRequests: [], remaining: 8
        )
        #expect(lowBalance == now.addingTimeInterval(15))

        let idle = DiscogsRateLimiter.backgroundReadyDate(
            now: now, lastNormalRequest: now.addingTimeInterval(-30), lastBackgroundSlot: now.addingTimeInterval(-10),
            recentRequests: [], remaining: 50
        )
        #expect(idle == now)
    }

    @Test func backgroundKeepsHalfOfTheQuotaForTheUser() {
        let recent = (0..<25).map { now.addingTimeInterval(-50 + Double($0)) }
        let ready = DiscogsRateLimiter.backgroundReadyDate(
            now: now, lastNormalRequest: nil, lastBackgroundSlot: nil, recentRequests: recent, remaining: nil
        )
        #expect(ready == now.addingTimeInterval(10.5))
    }

    @Test func retryDelayFollowsRetryAfterWithAMinimum() async throws {
        let limiter = DiscogsRateLimiter()
        let url = try #require(URL(string: "https://api.discogs.com"))
        func response(_ headers: [String: String]) -> HTTPURLResponse? {
            HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: headers)
        }
        let long = try #require(response(["Retry-After": "30"]))
        let short = try #require(response(["Retry-After": "1"]))
        let missing = try #require(response([:]))
        #expect(await limiter.retryDelay(after: long) == 30)
        #expect(await limiter.retryDelay(after: short) == 2)
        #expect(await limiter.retryDelay(after: missing) == 12)
    }

    @Test func discogsHeadersUpdateTheKnownBalance() async throws {
        let limiter = DiscogsRateLimiter()
        let url = try #require(URL(string: "https://api.discogs.com"))
        let response = try #require(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["X-Discogs-Ratelimit": "60", "X-Discogs-Ratelimit-Remaining": "42"]
        ))
        await limiter.recordResponse(response)
        #expect(await limiter.limit == 60)
        #expect(await limiter.remaining == 42)
    }
}

/// Webview de l'app : la session discogs.com ne quitte pas les domaines Discogs.
struct DiscogsWebPolicyTests {
    @Test(arguments: [
        "https://www.discogs.com/release/1",
        "https://discogs.com/user/alice",
        "https://auth.discogs.com/login",
        "https://accounts.google.com/o/oauth2",
        "about:blank"
    ])
    func allowedInTheWebView(_ raw: String) {
        #expect(DiscogsWebPolicy.allowsInAppNavigation(to: URL(string: raw)))
    }

    @Test(arguments: [
        "https://example.com",
        "https://discogs.com.evil.example/login",
        "https://notdiscogs.com",
        "http://www.discogs.com/release/1",
        "mailto:someone@example.com"
    ])
    func openedOutsideTheWebView(_ raw: String) {
        #expect(!DiscogsWebPolicy.allowsInAppNavigation(to: URL(string: raw)))
    }
}
