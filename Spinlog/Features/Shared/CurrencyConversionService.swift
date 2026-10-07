import Foundation

/// Service léger de conversion de devises, pour rapprocher des prix d'achat hétérogènes de la
/// devise principale de la collection. Utilise l'API gratuite frankfurter.dev (taux BCE), avec les
/// taux mis en cache 24h (mémoire + `UserDefaults`), et un repli sur une table de taux fixes si
/// hors ligne ou en cas d'échec réseau — volontairement approximative, elle ne sert qu'à éviter un
/// blocage total de l'affichage.
actor CurrencyConversionService {
    static let shared = CurrencyConversionService()

    private struct CachedRate {
        let rate: Double
        let fetchedAt: Date
    }

    private struct PersistedRate: Codable {
        let key: String
        let rate: Double
        let fetchedAt: Date
    }

    private struct FrankfurterResponse: Decodable {
        let rates: [String: Double]
    }

    private var cache: [String: CachedRate] = [:]
    private let cacheTTL: TimeInterval = DiscogsConstants.oneDayTTL
    private let userDefaultsKey = "com.spinlog.currencyRatesCache"
    /// Dernier échec de récupération par paire de devises. Sans ce délai, une API injoignable
    /// (réseau présent mais service en panne) était réinterrogée à CHAQUE conversion : le calcul
    /// du total investi enchaînait une requête par disque, chacune jusqu'au délai réseau maximal.
    private var lastFailureAt: [String: Date] = [:]
    private let failureRetryDelay: TimeInterval = 10 * 60

    /// Taux de repli approximatifs (1 unité de la devise -> USD), figés dans le code. Utilisés
    /// uniquement hors ligne ou en cas d'échec de l'API ; à ne jamais présenter comme des taux exacts.
    /// Couvre toutes les devises du marketplace Discogs : une devise absente était auparavant
    /// convertie à 1:1 (ex: 100 SEK comptés comme 100 EUR).
    private static let staticRatesToUSD: [String: Double] = [
        "USD": 1.0,
        "EUR": 1.08,
        "GBP": 1.27,
        "JPY": 0.0064,
        "CAD": 0.73,
        "CHF": 1.11,
        "AUD": 0.66,
        "NZD": 0.60,
        "SEK": 0.095,
        "BRL": 0.18,
        "MXN": 0.055,
        "ZAR": 0.055
    ]

    /// Charge le cache persistant directement dans l'initialiseur : un `init` synchrone
    /// d'acteur n'est pas isolé, donc appeler une méthode isolée comme `loadPersistedCache()`
    /// depuis ici n'est plus autorisé en mode de concurrence strict (Swift 6) — l'accès direct
    /// aux propriétés stockées reste lui autorisé pendant l'initialisation.
    private init() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let entries = try? JSONDecoder().decode([PersistedRate].self, from: data) else { return }
        for entry in entries {
            cache[entry.key] = CachedRate(rate: entry.rate, fetchedAt: entry.fetchedAt)
        }
    }

    /// Taux de conversion de `from` vers `to` (1 unité de `from` exprimée en `to`).
    func rate(from: String, to: String) async -> Double {
        let from = from.uppercased()
        let to = to.uppercased()
        guard from != to else { return 1.0 }

        let key = "\(from)_\(to)"
        if let cached = cache[key], Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.rate
        }

        let recentlyFailed = lastFailureAt[key].map { Date().timeIntervalSince($0) < failureRetryDelay } ?? false
        if !recentlyFailed {
            if let fetched = await fetchRate(from: from, to: to) {
                cache[key] = CachedRate(rate: fetched, fetchedAt: Date())
                lastFailureAt[key] = nil
                persistCache()
                return fetched
            }
            lastFailureAt[key] = Date()
        }

        // Un taux réel expiré reste plus juste que la table figée.
        if let stale = cache[key] {
            return stale.rate
        }
        return Self.staticFallbackRate(from: from, to: to)
    }

    func convert(_ amount: Double, from: String, to: String) async -> Double {
        amount * (await rate(from: from, to: to))
    }

    // MARK: - Réseau

    private func fetchRate(from: String, to: String) async -> Double? {
        guard await NetworkMonitor.shared.isConnected else { return nil }
        guard let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=\(from)&symbols=\(to)") else { return nil }
        // 10 s plutôt que les 60 s par défaut : en cas d'échec on retombe sur un taux approché,
        // inutile de bloquer l'affichage (total investi, alertes) aussi longtemps.
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
            return decoded.rates[to]
        } catch {
            return nil
        }
    }

    // MARK: - Repli statique

    private static func staticFallbackRate(from: String, to: String) -> Double {
        guard let fromToUSD = staticRatesToUSD[from], let toToUSD = staticRatesToUSD[to], toToUSD > 0 else {
            return 1.0
        }
        return fromToUSD / toToUSD
    }

    // MARK: - Cache persistant

    private func persistCache() {
        let entries = cache.map { PersistedRate(key: $0.key, rate: $0.value.rate, fetchedAt: $0.value.fetchedAt) }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

}
