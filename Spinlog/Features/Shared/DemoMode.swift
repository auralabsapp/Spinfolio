import Foundation

/// Mode démo : explorer l'app sans compte Discogs (testeurs App Review, utilisateurs curieux).
///
/// Rien n'est simulé côté écrans : `DiscogsAPIClient` détourne simplement les requêtes du compte
/// de démo vers `DemoServer` (collection et wantlist d'exemple embarquées dans
/// `DemoLibrary.json`), et envoie toutes les autres (fiches release, recherche, artistes...) au
/// vrai Discogs signées avec la seule clé de l'app. Toute modification du compte (ajout, retrait,
/// note, déplacement...) est refusée avec `APIError.demoReadOnly`. Les fonctions Premium sont
/// offertes en aperçu (`PremiumStore.isDemoPreview`), sans toucher à l'abonnement réel : l'offre
/// reste proposée (paywall au lancement, bannière de Réglages) pour pouvoir tester l'achat.
@MainActor
enum DemoMode {
    /// Nom fictif, choisi pour ne correspondre à aucun compte Discogs réel susceptible d'être
    /// consulté ailleurs dans l'app (profils publics, liens vers discogs.com...).
    static let username = "spinfolio_demo"
    static let credentials = DiscogsCredentials(token: "demo", tokenSecret: "demo")

    private static let activeKey = "demoModeActive"

    /// Limité à la session en cours : au lancement suivant, l'app revient toujours à l'écran de
    /// connexion (qui repropose la démo). Lu à chaque requête Discogs, d'où une simple valeur en
    /// mémoire.
    private(set) static var isActive = false

    /// Une démo était encore ouverte quand l'app a été fermée : ses données d'exemple (cache,
    /// tags, écoutes) n'ont pas été effacées et doivent l'être au lancement.
    static var hasLeftoverSession: Bool {
        UserDefaults.standard.bool(forKey: activeKey)
    }

    static func setActive(_ active: Bool) {
        isActive = active
        // Persisté uniquement comme marqueur de nettoyage (voir `hasLeftoverSession`).
        UserDefaults.standard.set(active, forKey: activeKey)
    }

    /// Branche le suivi de cote sur les champs de la collection d'exemple, pour que valeur,
    /// plus-value et états s'affichent sans réglage préalable.
    static func applyPreferences() {
        CollectionPreferencesStore.setPurchasePriceFieldId(DemoServer.purchasePriceFieldId, for: username)
        CollectionPreferencesStore.setMediaConditionFieldId(DemoServer.mediaConditionFieldId, for: username)
        CollectionPreferencesStore.setDefaultCurrency("EUR", for: username)
    }
}

/// Répond aux requêtes du compte de démo à partir de `DemoLibrary.json`, dans le format exact
/// de l'API Discogs : les modèles et view models existants décodent ces réponses sans le savoir.
@MainActor
enum DemoServer {
    private static let jazzFolderId = 9_000_001
    private static let electronicFolderId = 9_000_002
    static let purchasePriceFieldId = 4
    static let mediaConditionFieldId = 1

    private static let library: (collection: [[String: Any]], wants: [[String: Any]]) = {
        guard let url = Bundle.main.url(forResource: "DemoLibrary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], [])
        }
        return (object["collection"] as? [[String: Any]] ?? [], object["wants"] as? [[String: Any]] ?? [])
    }()

    /// Corps JSON de la réponse si la requête concerne le compte de démo, `nil` pour laisser la
    /// requête partir vers Discogs.
    static func response(path: String, method: String, queryItems: [URLQueryItem]) throws -> Data? {
        if path == "oauth/identity" {
            return try json(["id": 1, "username": DemoMode.username, "resource_url": ""])
        }
        // Estimations par état : réservées par Discogs à un vrai compte connecté.
        if path.hasPrefix("marketplace/price_suggestions") {
            throw DiscogsAPIClient.APIError.http(status: 404, message: nil)
        }

        let prefix = "users/\(DemoMode.username)"
        guard path == prefix || path.hasPrefix(prefix + "/") else { return nil }
        guard method == "GET" else { throw DiscogsAPIClient.APIError.demoReadOnly }

        let segments = path.dropFirst(prefix.count).split(separator: "/").map(String.init)
        let collection = library.collection
        let wants = library.wants

        switch segments {
        case []:
            return try json(profile)
        case ["collection", "folders"]:
            return try json(["folders": folders])
        case let s where s.count == 4 && s[0] == "collection" && s[1] == "folders" && s[3] == "releases":
            let folderId = Int(s[2]) ?? 0
            let items = folderId == 0 ? collection : collection.filter { ($0["folder_id"] as? Int) == folderId }
            return try paginated(items, key: "releases", queryItems: queryItems)
        case let s where s.count == 3 && s[0] == "collection" && s[1] == "releases":
            let releaseId = Int(s[2]) ?? -1
            let items = collection.filter { ($0["id"] as? Int) == releaseId }
            return try paginated(items, key: "releases", queryItems: [])
        case ["collection", "fields"]:
            return try json(["fields": fields])
        case ["collection", "value"]:
            return try json(["minimum": "€742.50", "median": "€1,186.20", "maximum": "€1,894.00"])
        case ["wants"]:
            return try paginated(wants, key: "wants", queryItems: queryItems)
        case let s where s.count == 2 && s[0] == "wants":
            let releaseId = Int(s[1]) ?? -1
            guard let item = wants.first(where: { ($0["id"] as? Int) == releaseId }) else {
                throw DiscogsAPIClient.APIError.http(status: 404, message: nil)
            }
            return try json(item)
        default:
            throw DiscogsAPIClient.APIError.http(status: 404, message: nil)
        }
    }

    // MARK: - Cote d'exemple

    /// Cote fictive d'une release, pour montrer la plus-value en démo : Discogs réserve ses
    /// estimations à un vrai compte connecté (voir `response`). Servie directement par
    /// `ReleaseActions`, sans passer par le cache des cotes (partagé entre comptes) ni par le
    /// Marketplace, qui affiche les vraies données Discogs.
    static func exampleMarketEstimate(releaseId: Int) -> MarketEstimate {
        let purchaseAmount = library.collection
            .first { ($0["id"] as? Int) == releaseId }
            .flatMap { $0["notes"] as? [[String: Any]] }?
            .first { ($0["field_id"] as? Int) == purchasePriceFieldId }
            .flatMap { $0["value"] as? String }
            .flatMap { PurchasePriceParser.parse($0, defaultCurrency: "EUR")?.amount }
        return exampleMarketEstimate(releaseId: releaseId, purchaseAmount: purchaseAmount)
    }

    /// Règle de calcul, extraite pour être testée : stable d'un affichage à l'autre (dérivée de
    /// l'identifiant), entre 0,75 et 1,95 fois le prix d'achat pour mêler plus- et moins-values,
    /// ou entre 15 et 60 € sans prix d'achat.
    nonisolated static func exampleMarketEstimate(releaseId: Int, purchaseAmount: Double?) -> MarketEstimate {
        let seed = abs(releaseId)
        let price: Double
        if let purchaseAmount, purchaseAmount > 0 {
            price = (purchaseAmount * (0.75 + Double(seed % 13) * 0.1)).rounded()
        } else {
            price = Double(15 + seed % 46)
        }
        return MarketEstimate(price: price, currency: "EUR", staleSince: nil)
    }

    // MARK: - Écoutes d'exemple

    /// Journal d'écoute fictif, pour que classements et podiums des statistiques ne soient pas
    /// vides en démo. Généré au démarrage de la démo (voir `DiscogsAuthManager.startDemo`) et
    /// effacé à sa sortie avec les autres données de démo.
    static func exampleListeningSessions(now: Date = Date()) -> [ListeningSession] {
        exampleListeningSessions(
            releaseIds: library.collection.compactMap { $0["id"] as? Int },
            now: now,
            calendar: .current
        )
    }

    /// Règle de génération, extraite pour être testée : écoutes réparties sur le mois en cours,
    /// le reste de l'année et l'année précédente, calculées à partir de `now` pour que les
    /// podiums du mois et de l'année soient toujours remplis, même le 1ᵉʳ janvier. Le tirage est
    /// déterministe et favorise les premiers disques, pour des classements nets.
    nonisolated static func exampleListeningSessions(releaseIds: [Int], now: Date, calendar: Calendar) -> [ListeningSession] {
        guard !releaseIds.isEmpty,
              let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)),
              let startOfLastYear = calendar.date(byAdding: .year, value: -1, to: startOfYear) else { return [] }

        var state: UInt64 = 0x5EED_CAFE
        func nextUnit() -> Double {
            // Générateur congruentiel linéaire (constantes de Knuth) : même journal à chaque démo.
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(UInt64(1) << 53)
        }

        var sessions: [ListeningSession] = []
        func spread(_ count: Int, from start: Date, to end: Date) {
            let span = end.timeIntervalSince(start)
            guard span > 0 else { return }
            for index in 0..<count {
                // Puissance > 1 : tirage concentré sur le début de la liste.
                let releaseIndex = min(releaseIds.count - 1, Int(Double(releaseIds.count) * pow(nextUnit(), 2.2)))
                let offset = span * (Double(index) + 0.5) / Double(count)
                sessions.append(ListeningSession(releaseId: releaseIds[releaseIndex], timestamp: start.addingTimeInterval(offset)))
            }
        }

        spread(14, from: startOfMonth, to: now)
        spread(46, from: startOfYear, to: startOfMonth)
        spread(36, from: startOfLastYear, to: startOfYear)
        return sessions.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Réponses

    private static var profile: [String: Any] {
        [
            "id": 1,
            "username": DemoMode.username,
            "name": String(localized: "Collection de démonstration"),
            "profile": "",
            "location": "",
            "registered": "2023-03-01T10:00:00-07:00",
            "num_collection": library.collection.count,
            "num_wantlist": library.wants.count,
            "curr_abbr": "EUR",
            "avatar_url": "",
            "uri": "",
            "resource_url": ""
        ]
    }

    private static var folders: [[String: Any]] {
        let collection = library.collection
        func count(_ id: Int) -> Int { collection.filter { ($0["folder_id"] as? Int) == id }.count }
        return [
            ["id": 0, "name": "All", "count": collection.count, "resource_url": ""],
            ["id": 1, "name": "Uncategorized", "count": count(1), "resource_url": ""],
            ["id": jazzFolderId, "name": "Jazz", "count": count(jazzFolderId), "resource_url": ""],
            ["id": electronicFolderId, "name": String(localized: "Électronique"), "count": count(electronicFolderId), "resource_url": ""]
        ]
    }

    /// Champs personnalisés par défaut d'un compte Discogs (mêmes identifiants et options).
    private static var fields: [[String: Any]] {
        let conditions = [
            "Mint (M)", "Near Mint (NM or M-)", "Very Good Plus (VG+)", "Very Good (VG)",
            "Good Plus (G+)", "Good (G)", "Fair (F)", "Poor (P)"
        ]
        return [
            ["id": 1, "name": "Media Condition", "type": "dropdown", "options": conditions],
            ["id": 2, "name": "Sleeve Condition", "type": "dropdown", "options": conditions + ["Generic", "No Cover"]],
            ["id": 3, "name": "Notes", "type": "textarea"],
            // Champ ajouté pour la démo, associé au suivi de cote par `DemoMode.applyPreferences`.
            ["id": purchasePriceFieldId, "name": String(localized: "Prix d'achat"), "type": "textarea"]
        ]
    }

    private static func paginated(_ items: [[String: Any]], key: String, queryItems: [URLQueryItem]) throws -> Data {
        let value: (String) -> Int? = { name in queryItems.first { $0.name == name }?.value.flatMap(Int.init) }
        let perPage = max(1, value("per_page") ?? 50)
        let page = max(1, value("page") ?? 1)
        let pages = max(1, Int((Double(items.count) / Double(perPage)).rounded(.up)))
        let slice = Array(items.dropFirst((page - 1) * perPage).prefix(perPage))
        return try json([
            "pagination": ["page": page, "pages": pages, "per_page": perPage, "items": items.count],
            key: slice
        ])
    }

    private static func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }
}

#if DEBUG
/// Arguments de lancement réservés aux tests d'interface (`SpinlogUITests`), absents des builds
/// Release : démarrer directement dans un état connu, sans compte Discogs ni paywall.
enum UITestLaunchOptions {
    /// Démarre directement sur la collection de démo.
    static let demoArgument = "-uiTestDemo"
    /// Démarre déconnecté, sur l'écran de connexion (qui propose la démo).
    static let signedOutArgument = "-uiTestSignedOut"

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static var startsInDemo: Bool { arguments.contains(demoArgument) }
    static var startsSignedOut: Bool { arguments.contains(signedOutArgument) }
    static var isActive: Bool { startsInDemo || startsSignedOut }

    /// Appliqué au lancement, avant le premier affichage. Déconnecte tout compte présent dans le
    /// Simulateur, pour que chaque test parte du même état.
    @MainActor
    static func apply() {
        guard isActive else { return }
        let auth = DiscogsAuthManager.shared
        if auth.isAuthenticated {
            auth.logout()
        }
        if startsInDemo {
            auth.startDemo()
        }
    }
}
#endif
