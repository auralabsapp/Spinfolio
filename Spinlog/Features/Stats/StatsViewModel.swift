import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class StatsViewModel {
    /// Libellés des parts regroupées des répartitions. Traduits, et utilisés à la fois pour
    /// l'affichage et comme clés de comparaison (`items(forGenre:)`…) : une seule source évite
    /// qu'un libellé traduit ne corresponde plus à la valeur comparée.
    static let othersLabel = String(localized: "Autres")
    static let unspecifiedLabel = String(localized: "Non spécifié")

    /// En dessous de ce nombre d'écoutes enregistrées, un classement n'est pas jugé assez
    /// représentatif pour être affiché (trop peu de données pour être pertinent).
    static let minimumListeningSessionsForRanking = 5

    @ObservationIgnored nonisolated(unsafe) private var observerTokens: [NSObjectProtocol] = []

    init() {
        // Recalcule les classements d'écoute dès qu'une session est ajoutée/retirée ailleurs
        // dans l'app (fiche release, widget...) — sans cet observateur, `topAlbums`/`topArtists`/
        // les podiums étaient recalculés à chaque rendu de l'écran Stats plutôt qu'une fois par
        // changement réel, contrairement à `allCollectionItems` un peu plus bas dans ce fichier.
        observerTokens = [
            NotificationCenter.default.addObserver(forName: .listeningLogChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.recomputeListeningStats()
                }
            }
        ]
    }

    deinit {
        observerTokens.forEach(NotificationCenter.default.removeObserver)
    }

    private(set) var isLoadingOverview = false
    /// Spécifique aux 3 appels de `loadCounters` (compteurs + derniers ajouts), indépendant de
    /// `isLoadingOverview` : ce dernier passe à `false` dès que le cache local est appliqué, bien
    /// avant que ces appels réseau n'aient forcément répondu (voir `loadOverview`). `true` dès la
    /// création du ViewModel plutôt que `false` : sans ça, le squelette de "Derniers ajouts"
    /// n'apparaissait qu'une fois `loadCounters` effectivement démarré, laissant un bref instant
    /// sans rien (ni squelette, ni contenu) à l'arrivée sur l'onglet.
    private(set) var isLoadingCounters = true

    private(set) var totalCollectionCount: Int?
    private(set) var totalWantlistCount: Int?
    private(set) var recentAdditions: [CollectionItem] = []
    private(set) var allCollectionItems: [CollectionItem] = [] {
        didSet {
            // Valeurs dérivées calculées une fois par changement de la collection, plutôt qu'à
            // chaque lecture : elles sont lues à chaque rendu de l'écran Stats, qui se redessine
            // toutes les 1,5 s pendant la résolution des masters.
            var releases: [Int: CollectionItem] = [:]
            for item in allCollectionItems where releases[item.releaseId] == nil {
                releases[item.releaseId] = item
            }
            releaseById = releases
            let names = allCollectionItems
                .map { ArtistShelfSortHelper.cleanDiscogsSuffix($0.basicInformation.artistNames) }
                .filter { !$0.isEmpty }
            uniqueArtistsCount = allCollectionItems.isEmpty ? nil : Set(names).count
            // `releaseById` ci-dessus vient de changer : les classements d'écoute, qui s'appuient
            // dessus pour résoudre un `releaseId` en disque affichable, doivent suivre.
            recomputeListeningStats()
        }
    }

    /// Nombre d'artistes distincts dans la collection, regroupés comme dans le classement
    /// "Top Artistes" (le suffixe de désambiguïsation Discogs, ex. « Artist (2) », est ignoré).
    private(set) var uniqueArtistsCount: Int?

    /// Une release par `releaseId` (peu importe l'exemplaire) pour retrouver titre/artiste/pochette
    /// à partir d'une session d'écoute, qui ne connaît que le `releaseId`.
    private var releaseById: [Int: CollectionItem] = [:]

    /// Nombre d'ajouts par année (date d'ajout dans la collection de l'utilisateur), trié par années décroissantes.
    /// Répartition par genre musical de la collection.
    private(set) var genreDistribution: [GenreDistributionEntry] = []
    private(set) var otherGenresNames: Set<String> = []

    /// Répartition par label (maison de disques) de la collection.
    private(set) var labelDistribution: [LabelDistributionEntry] = []
    private(set) var otherLabelsNames: Set<String> = []

    /// Répartition par support physique (Vinyles/CD/Cassettes/Autres) de la collection.
    private(set) var mediaFormatDistribution: [MediaFormatDistributionEntry] = []
    /// Détail par taille (12"/10"/7") au sein de la part "Vinyles", pour l'affichage au tap.
    private(set) var vinylSizeBreakdown: [VinylSizeBreakdownEntry] = []

    /// Classement complet des artistes de la collection, décroissant par nombre de disques.
    private(set) var topArtistsByCollectionCount: [(name: String, count: Int)] = []

    private(set) var additionsPerYear: [(year: Int, count: Int)] = []
    private(set) var isLoadingHistogram = false

    /// Répartition par année de sortie originale de l'album (Master Year), triée par années décroissantes.
    private(set) var originalYearsDistribution: [(year: Int, count: Int)] = []
    /// Progression de la résolution des masters (ex: résolus / total).
    private(set) var masterResolutionProgress: Double = 1.0
    private(set) var isResolvingMasters = false
    private(set) var missingMastersCount: Int = 0

    /// Estimation globale de la collection, basée sur l'historique réel des ventes Discogs.
    private(set) var collectionValue: CollectionValueResponse?
    private(set) var isLoadingValuation = false

    /// Historique local des estimations de collection (1 point max par jour), pour le graphique
    /// d'évolution. Aucune métadonnée disque n'y est associée (conformité CGU Discogs).
    private(set) var valueHistoryPoints: [(date: Date, low: Double, median: Double, high: Double)] = []

    /// Recharge uniquement l'historique de valeur depuis le stockage local, sans requête réseau —
    /// utilisé quand `CloudSyncEngine` reçoit un nouveau point d'un autre appareil pendant que cet
    /// écran est déjà ouvert (`loadOverview()` ne se redéclenche pas de lui-même dans ce cas).
    func refreshValueHistoryFromLocalStore() {
        guard let username = authManager.username else {
            valueHistoryPoints = []
            return
        }
        valueHistoryPoints = localStore.allCollectionSnapshots(username: username).map { ($0.date, $0.low, $0.median, $0.high) }
    }

    /// Total investi (somme des prix d'achat renseignés, convertis vers la devise par défaut) et
    /// cote actuelle de la collection, pour le bilan comparatif.
    private(set) var totalInvested: Double?
    private(set) var totalInvestedCurrency = "EUR"
    private(set) var isComputingInvested = false

    private let authManager = DiscogsAuthManager.shared
    private let localStore = LocalDataStore.shared
    private var histogramTask: Task<Void, Never>?
    private var masterResolutionTask: Task<Void, Never>?

    /// Dictionnaire en mémoire des années de masters connues [masterId: originalYear].
    private var masterYearsCache: [Int: Int] = [:]

    /// Affiche d'abord tout ce que le cache local permet (répartitions, classements, historique),
    /// sans attendre le réseau. Les compteurs Collection/Wantlist et les "derniers ajouts" sont 3
    /// appels légers mais, derrière un quota Discogs bas, `DiscogsRateLimiter` peut espacer chacun
    /// de 2 à 10s — ils n'alimentent que `countersRow`/`recentAdditionsSection`, qui savent déjà
    /// s'afficher sans leur donnée ("–", section absente), donc plus question qu'ils retiennent
    /// tout l'écran derrière le squelette pendant qu'ils répondent.
    func loadOverview() async {
        guard let username = authManager.username else { return }

        // Charge le cache local pérenne des MasterRecords (avant les calculs qui en dépendent)
        masterYearsCache = localStore.getAllMasterYears()

        // Une seule lecture (décodage complet) du cache de la collection, réutilisée par tous
        // les calculs : auparavant, il était décodé trois fois et les répartitions calculées
        // deux fois à chaque ouverture de l'écran.
        let cached = await localStore.getCollectionItems(username: username, folderId: DiscogsConstants.allFolderId)
        if !cached.isEmpty {
            applyCollectionItems(cached)
        }
        // Squelette complet réservé au tout premier lancement (aucun cache nulle part) : dès que
        // la collection est connue, même via ce cache, l'écran réel s'affiche — chaque section
        // encore en attente de données fraîches (histogramme, compteurs...) a déjà son propre état
        // intermédiaire (voir `isLoadingHistogram`, `countersRow`).
        isLoadingOverview = cached.isEmpty

        startHistogramLoad(hasFreshCache: !cached.isEmpty)

        async let counters: Void = loadCounters(username: username)
        async let valuation: Void = loadValuation()
        async let invested: Void = computeTotalInvestedIfNeeded()
        _ = await (counters, valuation, invested)
    }

    /// Compteurs Collection/Wantlist + derniers ajouts : 3 appels légers (`per_page` réduit),
    /// indépendants du reste de l'écran (voir `loadOverview`).
    private func loadCounters(username: String) async {
        isLoadingCounters = true
        defer { isLoadingCounters = false }
        guard let credentials = authManager.credentials else { return }
        do {
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
            totalCollectionCount = collectionResponse.pagination.items
            totalWantlistCount = wantlistResponse.pagination.items
            // Même animation que les autres sections de l'écran (répartitions, classements…) au
            // passage du squelette aux vraies pochettes, plutôt qu'un remplacement instantané.
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                recentAdditions = recentResponse.releases
            }
        } catch {
            // Sans réseau (ou erreur transitoire), on retombe sur le cache local pour les 2
            // compteurs qui ont un équivalent exact (contrairement à la cote de marché, qui
            // n'en a aucun) : seuls les "derniers ajouts" restent vides. Si même ce cache est
            // vide (jamais synchronisé), on laisse le compteur à `nil` plutôt que d'afficher un
            // 0 trompeur — `countersRow` affiche alors "–".
            let cachedCollection = await localStore.getCollectionItems(username: username, folderId: DiscogsConstants.allFolderId)
            let cachedWantlist = await localStore.getWantlistItems(username: username)
            if !cachedCollection.isEmpty {
                totalCollectionCount = cachedCollection.count
            }
            if !cachedWantlist.isEmpty {
                totalWantlistCount = cachedWantlist.count
            }
        }
    }

    private func loadValuation() async {
        guard let (username, credentials) = authManager.session else { return }
        isLoadingValuation = true
        collectionValue = try? await DiscogsAPIClient.shared.collectionValue(username: username, credentials: credentials)
        isLoadingValuation = false
        // Enregistrement quotidien de l'historique de valeur désactivé tant que le graphique
        // « Évolution de la cote » est masqué : ce sont des données Discogs qu'on n'a pas à garder
        // au-delà de 6 h (CGU de l'API). À réactiver seulement avec l'accord de Discogs.
        // recordCollectionSnapshotIfNeeded()
        refreshValueHistoryFromLocalStore()
    }

    /// Enregistre un nouveau point d'historique (au plus 1 par jour) à partir de la valeur de
    /// collection déjà chargée. `CollectionValueResponse` renvoie des montants déjà formatés par
    /// Discogs (ex. `"$960.00"`) : on les reparse pour en tirer des nombres exploitables en graphique.
    private func recordCollectionSnapshotIfNeeded() {
        guard let collectionValue, let username = authManager.username else { return }
        let oneDay: TimeInterval = DiscogsConstants.oneDayTTL
        if let latest = localStore.latestCollectionSnapshot(username: username), Date().timeIntervalSince(latest.date) < oneDay {
            return
        }
        guard let low = PurchasePriceParser.parseFormattedDiscogsAmount(collectionValue.minimum),
              let median = PurchasePriceParser.parseFormattedDiscogsAmount(collectionValue.median),
              let high = PurchasePriceParser.parseFormattedDiscogsAmount(collectionValue.maximum) else { return }
        localStore.saveCollectionSnapshot(username: username, currency: median.currency, low: low.amount, median: median.amount, high: high.amount)
    }

    /// Somme les prix d'achat renseignés sur la collection (déjà chargée en cache), convertis
    /// vers la devise par défaut de l'utilisateur, pour le bilan "Total investi vs Cote actuelle".
    func computeTotalInvestedIfNeeded() async {
        guard let username = authManager.username,
              let fieldId = CollectionPreferencesStore.purchasePriceFieldId(for: username) else { return }
        let currency = CollectionPreferencesStore.defaultCurrency(for: username)

        isComputingInvested = true
        // Sommé par devise d'abord, puis une seule conversion par devise : auparavant, chaque
        // disque attendait sa propre conversion (un passage par l'acteur, voire une requête).
        var amountsByCurrency: [String: Double] = [:]
        for item in allCollectionItems {
            let raw = item.value(forFieldId: fieldId).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, let parsed = PurchasePriceParser.parse(raw, defaultCurrency: currency) else { continue }
            amountsByCurrency[parsed.currency, default: 0] += parsed.amount
        }
        var total = 0.0
        for (sourceCurrency, amount) in amountsByCurrency {
            total += await CurrencyConversionService.shared.convert(amount, from: sourceCurrency, to: currency)
        }
        totalInvested = total
        totalInvestedCurrency = currency
        isComputingInvested = false
    }

    /// Remplace la collection analysée et recalcule toutes les répartitions qui en dépendent.
    private func applyCollectionItems(_ items: [CollectionItem]) {
        allCollectionItems = items
        additionsPerYear = Self.groupByYear(items)
        updateOriginalYearsDistribution()
        updateGenreDistribution()
        updateLabelDistribution()
        updateMediaFormatDistribution()
        updateTopArtistsByCollectionCount()
    }

    /// Recharge toute la collection depuis Discogs si le cache local est périmé (ou vide). Le
    /// cache, lui, a déjà été appliqué par `loadOverview` pour un affichage immédiat.
    private func startHistogramLoad(hasFreshCache: Bool) {
        histogramTask?.cancel()
        guard let username = authManager.username else { return }

        if hasFreshCache && !localStore.isCollectionStale(username: username, folderId: DiscogsConstants.allFolderId) {
            return
        }

        guard let credentials = authManager.credentials else { return }
        // Renonce si une autre synchronisation complète du même dossier est déjà en cours
        // (lancement à froid : `WidgetSnapshotSyncService`/`CollectionViewModel`/
        // `OfflineDownloadManager` peuvent aussi vouloir tout recharger en même temps) — le cache
        // sera de toute façon à jour une fois celle-ci terminée.
        guard localStore.beginFullCollectionSync(username: username, folderId: DiscogsConstants.allFolderId) else { return }
        isLoadingHistogram = true
        histogramTask = Task { [weak self] in
            guard let self else { return }
            defer { self.localStore.endFullCollectionSync(username: username, folderId: DiscogsConstants.allFolderId) }
            // Jamais déclenché par un geste explicite de l'utilisateur (ouverture de l'onglet
            // Stats avec un cache périmé) — priorité basse pour le quota Discogs, même principe
            // que `CollectionViewModel.startBackgroundSync`/`WidgetSnapshotSyncService`.
            await DiscogsRateLimiter.$priority.withValue(.background) {
                do {
                    let allItems = try await DiscogsAPIClient.shared.fetchAllCollectionItems(
                        username: username, folderId: DiscogsConstants.allFolderId, credentials: credentials
                    )
                    guard !Task.isCancelled else { return }
                    self.totalCollectionCount = allItems.count
                    await self.localStore.syncCollectionFolder(username: username, folderId: DiscogsConstants.allFolderId, fullItems: allItems)
                    self.applyCollectionItems(allItems)
                    // Le total investi dépend de la collection : le recalculer sur la version
                    // fraîche (il avait été calculé sur le cache, éventuellement périmé).
                    await self.computeTotalInvestedIfNeeded()
                } catch {
                    // On garde l'histogramme vide en cas d'échec.
                }
            }
            self.isLoadingHistogram = false
        }
    }

    // MARK: - Répartition par Genre Musical

    /// Calcule la répartition des genres musicaux sur l'ensemble de la collection.
    private func updateGenreDistribution() {
        guard !allCollectionItems.isEmpty else {
            genreDistribution = []
            otherGenresNames = []
            return
        }

        var counts: [String: Int] = [:]
        for item in allCollectionItems {
            let rawGenres = item.basicInformation.genres?.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? []
            if rawGenres.isEmpty {
                counts[Self.unspecifiedLabel, default: 0] += 1
            } else {
                for genre in rawGenres {
                    let clean = genre.trimmingCharacters(in: .whitespaces)
                    counts[clean, default: 0] += 1
                }
            }
        }

        let totalOccurrences = counts.values.reduce(0, +)
        guard totalOccurrences > 0 else {
            genreDistribution = []
            otherGenresNames = []
            return
        }

        let sorted = counts.sorted {
            if $0.value != $1.value {
                return $0.value > $1.value
            }
            return $0.key < $1.key
        }

        // On garde les 6 genres majeurs et on regroupe les restants dans "Autres"
        let maxMainSlices = 6
        var entries: [GenreDistributionEntry] = []
        var othersCount = 0
        var othersSet = Set<String>()

        for (index, pair) in sorted.enumerated() {
            if sorted.count > maxMainSlices && index >= maxMainSlices - 1 {
                othersCount += pair.value
                othersSet.insert(pair.key)
            } else {
                let pct = (Double(pair.value) / Double(totalOccurrences)) * 100.0
                entries.append(GenreDistributionEntry(name: pair.key, count: pair.value, percentage: pct))
            }
        }

        if othersCount > 0 {
            let pct = (Double(othersCount) / Double(totalOccurrences)) * 100.0
            entries.append(GenreDistributionEntry(name: Self.othersLabel, count: othersCount, percentage: pct))
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            self.otherGenresNames = othersSet
            self.genreDistribution = entries
        }
    }

    // MARK: - Répartition par Label

    /// Calcule la répartition par label (maison de disques) sur l'ensemble de la collection,
    /// même mécanique que `updateGenreDistribution`.
    private func updateLabelDistribution() {
        guard !allCollectionItems.isEmpty else {
            labelDistribution = []
            otherLabelsNames = []
            return
        }

        var counts: [String: Int] = [:]
        for item in allCollectionItems {
            let rawLabels = item.basicInformation.labels?.map { $0.name.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
            if rawLabels.isEmpty {
                counts[Self.unspecifiedLabel, default: 0] += 1
            } else {
                for label in rawLabels {
                    counts[label, default: 0] += 1
                }
            }
        }

        let totalOccurrences = counts.values.reduce(0, +)
        guard totalOccurrences > 0 else {
            labelDistribution = []
            otherLabelsNames = []
            return
        }

        let sorted = counts.sorted {
            if $0.value != $1.value {
                return $0.value > $1.value
            }
            return $0.key < $1.key
        }

        // On garde les 6 labels majeurs et on regroupe les restants dans "Autres"
        let maxMainSlices = 6
        var entries: [LabelDistributionEntry] = []
        var othersCount = 0
        var othersSet = Set<String>()

        for (index, pair) in sorted.enumerated() {
            if sorted.count > maxMainSlices && index >= maxMainSlices - 1 {
                othersCount += pair.value
                othersSet.insert(pair.key)
            } else {
                let pct = (Double(pair.value) / Double(totalOccurrences)) * 100.0
                entries.append(LabelDistributionEntry(name: pair.key, count: pair.value, percentage: pct))
            }
        }

        if othersCount > 0 {
            let pct = (Double(othersCount) / Double(totalOccurrences)) * 100.0
            entries.append(LabelDistributionEntry(name: Self.othersLabel, count: othersCount, percentage: pct))
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            self.otherLabelsNames = othersSet
            self.labelDistribution = entries
        }
    }

    /// Retourne la liste des disques correspondant à un label donné.
    func items(forLabel labelName: String) -> [CollectionItem] {
        if labelName == Self.othersLabel {
            return allCollectionItems.filter { item in
                let labels = item.basicInformation.labels?.map(\.name) ?? []
                return labels.contains { otherLabelsNames.contains($0) }
            }.sorted { item1, item2 in
                item1.basicInformation.title.localizedStandardCompare(item2.basicInformation.title) == .orderedAscending
            }
        } else if labelName == Self.unspecifiedLabel {
            return allCollectionItems.filter { item in
                let labels = item.basicInformation.labels?.map { $0.name.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
                return labels.isEmpty
            }.sorted { item1, item2 in
                item1.basicInformation.title.localizedStandardCompare(item2.basicInformation.title) == .orderedAscending
            }
        } else {
            return allCollectionItems.filter { item in
                item.basicInformation.labels?.contains { $0.name == labelName } == true
            }.sorted { item1, item2 in
                item1.basicInformation.title.localizedStandardCompare(item2.basicInformation.title) == .orderedAscending
            }
        }
    }

    // MARK: - Répartition par Support Physique

    /// Calcule la répartition Vinyles/CD/Cassettes/Autres, ainsi que le détail par taille au sein
    /// des vinyles (12"/10"/7"), à partir du format Discogs principal de chaque exemplaire.
    private func updateMediaFormatDistribution() {
        guard !allCollectionItems.isEmpty else {
            mediaFormatDistribution = []
            vinylSizeBreakdown = []
            return
        }

        var broadCounts: [String: Int] = [:]
        var vinylSizeCounts: [ShelfMediaCategory: Int] = [:]

        for item in allCollectionItems {
            let category = Release(from: item).shelfMediaCategory
            broadCounts[category.broadFormatLabel, default: 0] += 1
            if category == .vinyl12 || category == .vinyl10 || category == .vinyl7 {
                vinylSizeCounts[category, default: 0] += 1
            }
        }

        let total = broadCounts.values.reduce(0, +)
        guard total > 0 else {
            mediaFormatDistribution = []
            vinylSizeBreakdown = []
            return
        }

        // Ordre fixe et logique (pas un tri par volume) : Vinyles, CD, Cassettes, Autres.
        let order = [ShelfMediaCategory.vinyl12, .cd, .cassette, .other].map(\.broadFormatLabel)
        let entries = order.compactMap { label -> MediaFormatDistributionEntry? in
            guard let count = broadCounts[label], count > 0 else { return nil }
            let pct = (Double(count) / Double(total)) * 100.0
            return MediaFormatDistributionEntry(name: label, count: count, percentage: pct)
        }

        let sizeOrder: [ShelfMediaCategory] = [.vinyl12, .vinyl10, .vinyl7]
        let sizeEntries = sizeOrder.compactMap { category -> VinylSizeBreakdownEntry? in
            guard let count = vinylSizeCounts[category], count > 0 else { return nil }
            return VinylSizeBreakdownEntry(category: category, count: count)
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            self.mediaFormatDistribution = entries
            self.vinylSizeBreakdown = sizeEntries
        }
    }

    /// Retourne la liste des disques appartenant à un support donné ("Vinyles", "CD"...).
    func items(forMediaFormat name: String) -> [CollectionItem] {
        allCollectionItems.filter { Release(from: $0).shelfMediaCategory.broadFormatLabel == name }
            .sorted { $0.basicInformation.title.localizedStandardCompare($1.basicInformation.title) == .orderedAscending }
    }

    /// Retourne la liste des disques d'une taille de vinyle précise (détail au tap de "Vinyles").
    func items(forShelfCategory category: ShelfMediaCategory) -> [CollectionItem] {
        allCollectionItems.filter { Release(from: $0).shelfMediaCategory == category }
            .sorted { $0.basicInformation.title.localizedStandardCompare($1.basicInformation.title) == .orderedAscending }
    }

    /// Retourne la liste des disques correspondant à un genre donné.
    func items(forGenre genreName: String) -> [CollectionItem] {
        unsortedItems(forGenre: genreName).sorted { item1, item2 in
            item1.basicInformation.title.localizedStandardCompare(item2.basicInformation.title) == .orderedAscending
        }
    }

    /// Même filtre que `items(forGenre:)`, sans le tri alphabétique (coûteux) : suffisant pour
    /// compter, ce que fait `styleBreakdown`, évalué à chaque rendu de l'écran Stats.
    private func unsortedItems(forGenre genreName: String) -> [CollectionItem] {
        if genreName == Self.othersLabel {
            return allCollectionItems.filter { item in
                let genres = item.basicInformation.genres ?? []
                return genres.contains { otherGenresNames.contains($0) }
            }
        } else if genreName == Self.unspecifiedLabel {
            return allCollectionItems.filter { item in
                let genres = item.basicInformation.genres?.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? []
                return genres.isEmpty
            }
        } else {
            return allCollectionItems.filter { item in
                item.basicInformation.genres?.contains(genreName) == true
            }
        }
    }

    /// Détail des styles musicaux parmi les disques d'un genre donné, triés par nombre
    /// d'occurrences (les 6 styles majeurs). Un disque ayant plusieurs styles compte pour
    /// chacun d'eux, donc la somme des occurrences peut dépasser le nombre de disques du genre.
    func styleBreakdown(forGenre genreName: String) -> [StyleBreakdownEntry] {
        var counts: [String: Int] = [:]
        for item in unsortedItems(forGenre: genreName) {
            let styles = item.basicInformation.styles?.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? []
            for style in styles {
                counts[style.trimmingCharacters(in: .whitespaces), default: 0] += 1
            }
        }
        guard !counts.isEmpty else { return [] }

        let maxStyles = 6
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(maxStyles)
            .map { StyleBreakdownEntry(name: $0.key, count: $0.value) }
    }

    /// Retourne la liste des disques d'un genre donné qui portent aussi un style précis
    /// (détail affiché au tap d'un style dans `styleBreakdown`).
    func items(forGenre genreName: String, style styleName: String) -> [CollectionItem] {
        items(forGenre: genreName).filter { $0.basicInformation.styles?.contains(styleName) == true }
    }

    // MARK: - Classement des Artistes

    /// Calcule le classement complet des artistes de la collection (nombre de
    /// disques possédés), en regroupant comme dans le classement d'écoute "Top Artistes" (le
    /// suffixe de désambiguïsation Discogs, ex. « Artist (2) », est ignoré).
    private func updateTopArtistsByCollectionCount() {
        guard !allCollectionItems.isEmpty else {
            topArtistsByCollectionCount = []
            return
        }

        var counts: [String: Int] = [:]
        for item in allCollectionItems {
            let name = ArtistShelfSortHelper.cleanDiscogsSuffix(item.basicInformation.artistNames)
            guard !name.isEmpty else { continue }
            counts[name, default: 0] += 1
        }

        let sorted = counts.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
        }
        let ranked = sorted.map { (name: $0.key, count: $0.value) }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            self.topArtistsByCollectionCount = ranked
        }
    }

    /// Retourne la liste des disques d'un artiste donné (même regroupement que le classement).
    /// Calculée hors du fil principal, comme les listes des histogrammes : le filtre nettoie le
    /// nom d'artiste de chaque disque de la collection.
    func items(forArtist artistName: String) async -> [CollectionItem] {
        let source = allCollectionItems
        return await Task.detached(priority: .userInitiated) {
            Self.sortedByTitle(source.filter {
                ArtistShelfSortHelper.cleanDiscogsSuffix($0.basicInformation.artistNames) == artistName
            })
        }.value
    }

    // MARK: - Résolution & Histogramme des Années Originales (Master Years)

    /// Met à jour la distribution des années originales en utilisant le cache existant,
    /// puis déclenche le service d'arrière-plan pour résoudre les masters manquants.
    private func updateOriginalYearsDistribution() {
        guard !allCollectionItems.isEmpty else { return }

        // Recalcule la répartition actuelle avec les données déjà connues (triée par années décroissantes)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            self.originalYearsDistribution = computeOriginalYears(from: allCollectionItems, masterYears: masterYearsCache)
        }

        // Identifie les masterIds manquants
        var missingMasterIds = Set<Int>()
        for item in allCollectionItems {
            if let masterId = item.basicInformation.masterId, masterId > 0 {
                if masterYearsCache[masterId] == nil {
                    missingMasterIds.insert(masterId)
                }
            }
        }

        missingMastersCount = missingMasterIds.count
        if missingMasterIds.isEmpty {
            isResolvingMasters = false
            masterResolutionProgress = 1.0
            return
        }

        isResolvingMasters = true
        updateMasterResolutionProgress()

        masterResolutionTask?.cancel()
        let missingList = Array(missingMasterIds)

        masterResolutionTask = Task { [weak self] in
            await MasterResolutionService.shared.resolveMasters(missingMasterIds: missingList, subscriberKey: "stats") { [weak self] resolved, total, masterId, year in
                guard let self else { return }
                self.masterYearsCache[masterId] = year
                self.missingMastersCount = max(0, total - resolved)
                self.updateMasterResolutionProgress()

                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    self.originalYearsDistribution = self.computeOriginalYears(from: self.allCollectionItems, masterYears: self.masterYearsCache)
                }

                if resolved >= total {
                    self.isResolvingMasters = false
                    self.masterResolutionProgress = 1.0
                }
            }
        }
    }

    /// Nombre d'éléments de la collection dont l'année originale est déjà résolue ou connue
    /// (soit via le cache du master, soit directement via l'année de pressage s'il n'y a pas de master).
    private func currentResolvedCollectionItemsCount() -> Int {
        guard !allCollectionItems.isEmpty else { return 0 }
        var resolved = 0
        for item in allCollectionItems {
            if let masterId = item.basicInformation.masterId, masterId > 0 {
                if masterYearsCache[masterId] != nil {
                    resolved += 1
                }
            } else {
                resolved += 1
            }
        }
        return resolved
    }

    /// Calcule systématiquement l'avancement par rapport au nombre total d'éléments dans la collection.
    private func updateMasterResolutionProgress() {
        let total = allCollectionItems.count
        guard total > 0 else {
            masterResolutionProgress = 1.0
            return
        }
        let resolved = currentResolvedCollectionItemsCount()
        masterResolutionProgress = min(1.0, max(0.0, Double(resolved) / Double(total)))
    }

    /// Calcule le regroupement de la collection par année originale.
    /// Pour chaque album unique :
    /// - Si un masterId > 0 existe et que son année est résolue (> 0), on utilise cette année de master.
    /// - Si le masterId est absent, nul (0), ou sans année master, on utilise l'année de pressage de la release (`basicInformation.year`).
    /// Trié par années décroissantes (de la plus récente à la plus ancienne).
    private func computeOriginalYears(from items: [CollectionItem], masterYears: [Int: Int]) -> [(year: Int, count: Int)] {
        var counts: [Int: Int] = [:]

        for item in items {
            let originalYear: Int?
            if let masterId = item.basicInformation.masterId, masterId > 0, let cachedYear = masterYears[masterId], cachedYear > 0 {
                originalYear = cachedYear
            } else if let releaseYear = item.basicInformation.year, releaseYear > 0 {
                originalYear = releaseYear
            } else {
                originalYear = nil
            }

            if let year = originalYear, year > 1900, year <= Calendar.current.component(.year, from: Date()) {
                counts[year, default: 0] += 1
            }
        }

        // Tri par années décroissantes
        return counts.sorted { $0.key > $1.key }.map { (year: $0.key, count: $0.value) }
    }

    /// Année originale résolue pour un exemplaire, à partir du cache courant des masters
    /// (même règle que `computeOriginalYears`) : master year si connue, sinon année de pressage.
    nonisolated private static func resolvedOriginalYear(for item: CollectionItem, masterYears: [Int: Int]) -> Int? {
        if let masterId = item.basicInformation.masterId, masterId > 0, let cachedYear = masterYears[masterId], cachedYear > 0 {
            return cachedYear
        } else if let releaseYear = item.basicInformation.year, releaseYear > 0 {
            return releaseYear
        }
        return nil
    }

    nonisolated private static func sortedByTitle(_ items: [CollectionItem]) -> [CollectionItem] {
        items.sorted { item1, item2 in
            item1.basicInformation.title.localizedStandardCompare(item2.basicInformation.title) == .orderedAscending
        }
    }

    /// Retourne la liste des disques de la collection sortis à une année originale donnée.
    /// Filtre et tri de toute la collection : calculés hors du fil principal, pour ne pas retarder
    /// l'affichage de la sélection au toucher d'une barre.
    func items(forOriginalYear year: Int) async -> [CollectionItem] {
        let source = allCollectionItems
        let masterYears = masterYearsCache
        return await Task.detached(priority: .userInitiated) {
            Self.sortedByTitle(source.filter { Self.resolvedOriginalYear(for: $0, masterYears: masterYears) == year })
        }.value
    }

    /// Répartition de `originalYearsDistribution` regroupée par décennie (1990 → 1990-1999),
    /// pour une vue moins dense sur une grande collection. Triée par décennies décroissantes.
    var originalYearsDistributionByDecade: [(decade: Int, count: Int)] {
        var counts: [Int: Int] = [:]
        for entry in originalYearsDistribution {
            let decade = (entry.year / 10) * 10
            counts[decade, default: 0] += entry.count
        }
        return counts.sorted { $0.key > $1.key }.map { (decade: $0.key, count: $0.value) }
    }

    /// Retourne la liste des disques de la collection sortis durant une décennie donnée (ex. 1990 → 1990-1999).
    func items(forOriginalDecade decade: Int) async -> [CollectionItem] {
        let source = allCollectionItems
        let masterYears = masterYearsCache
        return await Task.detached(priority: .userInitiated) {
            Self.sortedByTitle(source.filter { item in
                guard let year = Self.resolvedOriginalYear(for: item, masterYears: masterYears) else { return false }
                return year >= decade && year < decade + 10
            })
        }.value
    }

    /// Retourne la liste des disques de la collection ajoutés durant une année donnée,
    /// triés du plus récent au plus ancien par date d'ajout.
    func items(forYear year: Int) async -> [CollectionItem] {
        // Pas de repli réseau/cache ici si `allCollectionItems` est encore vide : cette méthode
        // n'est appelée qu'au tap d'une barre de l'histogramme "Exemplaires ajoutés par année",
        // qui ne peut lui-même s'afficher qu'une fois `allCollectionItems` déjà peuplé.
        let source = allCollectionItems
        return await Task.detached(priority: .userInitiated) {
            Self.itemsAdded(in: year, from: source)
        }.value
    }

    /// Date d'ajout lue une seule fois par disque (et non à chaque comparaison du tri).
    nonisolated static func itemsAdded(in year: Int, from source: [CollectionItem]) -> [CollectionItem] {
        let calendar = Calendar.current
        let dated: [(item: CollectionItem, date: Date)] = source.compactMap { item in
            guard let date = item.dateAddedDate, calendar.component(.year, from: date) == year else { return nil }
            return (item, date)
        }
        return dated.sorted { first, second in
            if first.date != second.date { return first.date > second.date }
            return first.item.basicInformation.title.localizedStandardCompare(second.item.basicInformation.title) == .orderedAscending
        }.map(\.item)
    }

    /// Regroupe les dates d'ajout par année, triées par années décroissantes.
    private static func groupByYear(_ items: [CollectionItem]) -> [(year: Int, count: Int)] {
        var counts: [Int: Int] = [:]
        for item in items {
            guard let date = item.dateAddedDate else { continue }
            let year = Calendar.current.component(.year, from: date)
            counts[year, default: 0] += 1
        }
        return counts.sorted { $0.key > $1.key }.map { (year: $0.key, count: $0.value) }
    }

    // MARK: - Tops & Palmarès d'écoute (fonctionnalité premium)

    private let listeningStore = ListeningLogStore.shared

    var totalListeningSessionsCount: Int {
        listeningStore.sessions.count
    }

    /// Classement des releases les plus écoutées de la collection, du plus au moins écouté.
    /// Vide tant que le nombre total d'écoutes enregistrées est trop faible pour être pertinent.
    /// Recalculé par `recomputeListeningStats()` plutôt qu'à chaque lecture (voir son commentaire).
    private(set) var topAlbums: [TopAlbumEntry] = []

    /// Classement des artistes dont les disques cumulent le plus d'écoutes, tous exemplaires
    /// confondus (ex. "Miles Davis : 27 sessions réparties sur 3 disques").
    private(set) var topArtists: [TopArtistEntry] = []

    /// Nombre d'écoutes enregistrées depuis le début du mois calendaire en cours.
    var monthlyListeningSessionsCount: Int {
        guard let startOfMonth = Self.startOfCurrentMonth else { return 0 }
        return listeningStore.sessions.filter { $0.timestamp >= startOfMonth }.count
    }

    /// Nombre d'écoutes enregistrées depuis le début de l'année civile en cours.
    var yearlyListeningSessionsCount: Int {
        guard let startOfYear = Self.startOfCurrentYear else { return 0 }
        return listeningStore.sessions.filter { $0.timestamp >= startOfYear }.count
    }

    /// Podium (top 3) des albums les plus écoutés depuis le début du mois : les coups de cœur
    /// récents, "en boucle" en ce moment.
    private(set) var monthlyPodium: [TopAlbumEntry] = []

    /// Podium (top 3) des albums les plus écoutés depuis le début de l'année : les classiques
    /// intemporels de la collection, ceux qui reviennent toute l'année.
    private(set) var yearlyPodium: [TopAlbumEntry] = []

    /// Recalcule `topAlbums`/`topArtists`/les podiums en une fois, appelé depuis le `didSet` de
    /// `allCollectionItems` et depuis l'observateur de `.listeningLogChanged` — plutôt que des
    /// propriétés calculées relisant `listeningStore.sessions` à chaque rendu de l'écran Stats,
    /// qui se redessine toutes les 1,5 s pendant la résolution des masters (même motivation que
    /// le cache déjà en place sur `allCollectionItems`).
    private func recomputeListeningStats() {
        if totalListeningSessionsCount >= Self.minimumListeningSessionsForRanking {
            topAlbums = rankedAlbums(sessions: listeningStore.sessions)
            topArtists = computeTopArtists()
        } else {
            topAlbums = []
            topArtists = []
        }

        if monthlyListeningSessionsCount >= Self.minimumListeningSessionsForRanking,
           let startOfMonth = Self.startOfCurrentMonth {
            let sessionsThisMonth = listeningStore.sessions.filter { $0.timestamp >= startOfMonth }
            monthlyPodium = Array(rankedAlbums(sessions: sessionsThisMonth).prefix(3))
        } else {
            monthlyPodium = []
        }

        if yearlyListeningSessionsCount >= Self.minimumListeningSessionsForRanking,
           let startOfYear = Self.startOfCurrentYear {
            let sessionsThisYear = listeningStore.sessions.filter { $0.timestamp >= startOfYear }
            yearlyPodium = Array(rankedAlbums(sessions: sessionsThisYear).prefix(3))
        } else {
            yearlyPodium = []
        }
    }

    private func computeTopArtists() -> [TopArtistEntry] {
        let releases = releaseById
        var playsByArtist: [String: Int] = [:]
        var releasesByArtist: [String: Set<Int>] = [:]
        var discogsArtistsByName: [String: [ReleaseArtist]] = [:]

        for session in listeningStore.sessions {
            guard let item = releases[session.releaseId] else { continue }
            let artist = ArtistShelfSortHelper.cleanDiscogsSuffix(item.basicInformation.artistNames)
            guard !artist.isEmpty else { continue }
            playsByArtist[artist, default: 0] += 1
            releasesByArtist[artist, default: []].insert(session.releaseId)
            if discogsArtistsByName[artist] == nil {
                discogsArtistsByName[artist] = item.basicInformation.artists ?? []
            }
        }

        return playsByArtist.map { name, totalPlays in
            TopArtistEntry(
                name: name,
                totalPlays: totalPlays,
                releaseCount: releasesByArtist[name]?.count ?? 0,
                artists: discogsArtistsByName[name] ?? []
            )
        }
        .sorted { $0.totalPlays != $1.totalPlays ? $0.totalPlays > $1.totalPlays : $0.name < $1.name }
    }

    private func rankedAlbums(sessions: [ListeningSession]) -> [TopAlbumEntry] {
        let releases = releaseById
        var counts: [Int: Int] = [:]
        for session in sessions {
            counts[session.releaseId, default: 0] += 1
        }
        return counts.compactMap { releaseId, count -> TopAlbumEntry? in
            guard let item = releases[releaseId] else { return nil }
            return TopAlbumEntry(item: item, playCount: count)
        }
        .sorted { $0.playCount != $1.playCount ? $0.playCount > $1.playCount : $0.item.basicInformation.title < $1.item.basicInformation.title }
    }

    private static var startOfCurrentMonth: Date? {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))
    }

    private static var startOfCurrentYear: Date? {
        Calendar.current.date(from: Calendar.current.dateComponents([.year], from: Date()))
    }
}
