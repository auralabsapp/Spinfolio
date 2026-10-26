import Foundation

/// Lectures Discogs et calculs asynchrones de l'onglet Stats, sans état : chaque fonction
/// renvoie un résultat que `StatsViewModel` applique (et revérifie le compte au retour).
enum StatsDataService {
    /// Compteurs Collection/Wantlist et 10 derniers ajouts.
    struct Counters {
        let collectionCount: Int
        let wantlistCount: Int
        let recentAdditions: [CollectionItem]
    }

    /// 3 appels légers (`per_page` réduit), lancés en parallèle.
    static func fetchCounters(username: String, credentials: DiscogsCredentials) async throws -> Counters {
        async let collectionCountRequest = DiscogsAPIClient.shared.collectionItems(
            username: username, folderId: DiscogsConstants.allFolderId, page: 1, perPage: 1, credentials: credentials
        )
        async let wantlistCountRequest = DiscogsAPIClient.shared.wantlist(
            username: username, page: 1, perPage: 1, credentials: credentials
        )
        async let recentRequest = DiscogsAPIClient.shared.collectionItems(
            username: username, folderId: DiscogsConstants.allFolderId, page: 1, perPage: 10, sort: "added", sortOrder: "desc", credentials: credentials
        )
        let (collectionResponse, wantlistResponse, recentResponse) = try await (collectionCountRequest, wantlistCountRequest, recentRequest)
        return Counters(
            collectionCount: collectionResponse.pagination.items,
            wantlistCount: wantlistResponse.pagination.items,
            recentAdditions: recentResponse.releases
        )
    }

    /// Repli hors ligne pour les deux compteurs qui ont un équivalent exact dans le cache
    /// (contrairement à la cote de marché). `nil` si ce cache est vide (jamais synchronisé),
    /// plutôt qu'un 0 trompeur : l'écran affiche alors « – ».
    static func cachedCounts(username: String) async -> (collection: Int?, wantlist: Int?) {
        let localStore = LocalDataStore.shared
        let cachedCollection = await localStore.getCollectionItems(username: username, folderId: DiscogsConstants.allFolderId)
        let cachedWantlist = await localStore.getWantlistItems(username: username)
        return (cachedCollection.isEmpty ? nil : cachedCollection.count, cachedWantlist.isEmpty ? nil : cachedWantlist.count)
    }

    /// Total des prix d'achat renseignés, converti vers la devise par défaut du compte ; `nil`
    /// si aucun champ « prix d'achat » n'est configuré. Une seule conversion par devise (et non
    /// par disque, qui attendait chacun un passage par l'acteur, voire une requête).
    static func totalInvested(of items: [CollectionItem], username: String) async -> (total: Double, currency: String)? {
        guard let fieldId = CollectionPreferencesStore.purchasePriceFieldId(for: username) else { return nil }
        let currency = CollectionPreferencesStore.defaultCurrency(for: username)
        var total = 0.0
        for (sourceCurrency, amount) in purchaseAmountsByCurrency(of: items, fieldId: fieldId, defaultCurrency: currency) {
            total += await CurrencyConversionService.shared.convert(amount, from: sourceCurrency, to: currency)
        }
        return (total, currency)
    }

    /// Prix d'achat renseignés, additionnés par devise (une devise absente du champ prend celle
    /// par défaut). Fonction pure, testée dans `StatsCalculationTests`.
    static func purchaseAmountsByCurrency(
        of items: [CollectionItem],
        fieldId: Int,
        defaultCurrency: String
    ) -> [String: Double] {
        var amountsByCurrency: [String: Double] = [:]
        for item in items {
            let raw = item.value(forFieldId: fieldId).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, let parsed = PurchasePriceParser.parse(raw, defaultCurrency: defaultCurrency) else { continue }
            amountsByCurrency[parsed.currency, default: 0] += parsed.amount
        }
        return amountsByCurrency
    }

    /// Enregistre un nouveau point d'historique (au plus 1 par jour) à partir de la valeur de
    /// collection. `CollectionValueResponse` renvoie des montants déjà formatés par Discogs (ex.
    /// `"$960.00"`) : on les reparse pour en tirer des nombres exploitables en graphique.
    /// Appel désactivé tant que le graphique « Évolution de la cote » est masqué : ce sont des
    /// données Discogs qu'on n'a pas à garder au-delà de 6 h (CGU de l'API). À réactiver
    /// seulement avec l'accord de Discogs (voir `StatsViewModel.loadValuation`).
    static func recordCollectionSnapshotIfNeeded(_ collectionValue: CollectionValueResponse, username: String) {
        let localStore = LocalDataStore.shared
        if let latest = localStore.latestCollectionSnapshot(username: username),
           Date().timeIntervalSince(latest.date) < DiscogsConstants.oneDayTTL {
            return
        }
        guard let low = PurchasePriceParser.parseFormattedDiscogsAmount(collectionValue.minimum),
              let median = PurchasePriceParser.parseFormattedDiscogsAmount(collectionValue.median),
              let high = PurchasePriceParser.parseFormattedDiscogsAmount(collectionValue.maximum) else { return }
        localStore.saveCollectionSnapshot(username: username, currency: median.currency, low: low.amount, median: median.amount, high: high.amount)
    }
}
