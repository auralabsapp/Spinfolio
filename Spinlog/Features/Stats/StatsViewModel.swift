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
            },
            addLibraryObserver(for: .collectionItemAdded, payloadKey: "item") { [weak self] (item: CollectionItem) in
                self?.handleCollectionItemAdded(item)
            },
            addCollectionRemovalObserver { [weak self] releaseId, instanceId in
                self?.handleCollectionItemRemoved(releaseId: releaseId, instanceId: instanceId)
            },
            addCollectionReplacementObserver { [weak self] oldInstanceId, newItem in
                self?.handleCollectionInstanceReplaced(oldInstanceId: oldInstanceId, newItem: newItem)
            }
        ]
    }

    /// Exemplaires retirés pendant la session : Discogs peut encore les renvoyer quelques instants
    /// dans la liste des derniers ajouts, ils sont écartés de la réponse (voir `loadCounters`).
    private var locallyRemovedInstanceIds: Set<Int> = []

    // MARK: - Suivi des changements faits ailleurs dans l'app

    private var collectionState: StatsCollectionChanges.State {
        StatsCollectionChanges.State(
            allItems: allCollectionItems,
            recentAdditions: recentAdditions,
            totalCount: totalCollectionCount,
            locallyRemovedInstanceIds: locallyRemovedInstanceIds
        )
    }

    private func apply(_ state: StatsCollectionChanges.State, animated: Bool = true) {
        locallyRemovedInstanceIds = state.locallyRemovedInstanceIds
        if state.allItemsChanged {
            applyCollectionItems(state.allItems)
        }
        if animated {
            withAnimation(.statsContentChange) {
                recentAdditions = state.recentAdditions
            }
        } else {
            recentAdditions = state.recentAdditions
        }
        totalCollectionCount = state.totalCount
    }

    private func handleCollectionItemAdded(_ item: CollectionItem) {
        apply(StatsCollectionChanges.adding(item, to: collectionState))
    }

    private func handleCollectionItemRemoved(releaseId: Int, instanceId: Int?) {
        apply(StatsCollectionChanges.removing(releaseId: releaseId, instanceId: instanceId, from: collectionState))
    }

    private func handleCollectionInstanceReplaced(oldInstanceId: Int, newItem: CollectionItem) {
        apply(StatsCollectionChanges.replacing(oldInstanceId: oldInstanceId, with: newItem, in: collectionState), animated: false)
    }

    deinit {
        observerTokens.forEach(NotificationCenter.default.removeObserver)
    }

    /// Arrête les chargements de fond lancés pour le compte qu'on quitte (déconnexion, sortie de
    /// démo) : sinon ils continuaient avec ses identifiants et consommaient le quota Discogs.
    func cancelAccountTasks() {
        histogramTask?.cancel()
        histogramTask = nil
        masterYearsResolver.cancel()
        isLoadingHistogram = false
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
            styleBreakdownCache = [:]
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

    /// Répartition par genre musical de la collection.
    private(set) var genreDistribution: [GenreDistributionEntry] = []
    private(set) var otherGenresNames: Set<String> = [] {
        didSet { styleBreakdownCache = [:] }
    }
    /// Détail par style de chaque genre déjà sélectionné, vidé quand la collection ou le
    /// regroupement « Autres » change : lu par `body`, il refiltrait toute la collection à chaque
    /// rendu de l'écran tant qu'un genre restait sélectionné.
    @ObservationIgnored private var styleBreakdownCache: [String: [StyleBreakdownEntry]] = [:]

    /// Répartition par label (maison de disques) de la collection.
    private(set) var labelDistribution: [LabelDistributionEntry] = []
    private(set) var otherLabelsNames: Set<String> = []

    /// Répartition par support physique (Vinyles/CD/Cassettes/Autres) de la collection.
    private(set) var mediaFormatDistribution: [MediaFormatDistributionEntry] = []
    /// Détail par taille (12"/10"/7") au sein de la part "Vinyles", pour l'affichage au tap.
    private(set) var vinylSizeBreakdown: [VinylSizeBreakdownEntry] = []

    /// Classement complet des artistes de la collection, décroissant par nombre de disques.
    private(set) var topArtistsByCollectionCount: [(name: String, count: Int)] = []

    /// Nombre d'ajouts par année (date d'ajout dans la collection), années décroissantes.
    private(set) var additionsPerYear: [(year: Int, count: Int)] = []
    private(set) var isLoadingHistogram = false

    /// Années originales (année du master) et résolution de fond des masters manquants.
    private let masterYearsResolver = StatsMasterYearsResolver()
    /// Répartition par année de sortie originale de l'album (Master Year), années décroissantes.
    var originalYearsDistribution: [(year: Int, count: Int)] { masterYearsResolver.distribution }
    /// Progression de la résolution des masters (résolus / total).
    var masterResolutionProgress: Double { masterYearsResolver.progress }
    var isResolvingMasters: Bool { masterYearsResolver.isResolving }
    var missingMastersCount: Int { masterYearsResolver.missingCount }

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
    /// Dernière interrogation des compteurs et de la valeur (voir `loadOverview`).
    @ObservationIgnored private var overviewThrottle = ReloadThrottle()
    private var histogramTask: Task<Void, Never>?


    /// Affiche d'abord tout ce que le cache local permet (répartitions, classements, historique),
    /// sans attendre le réseau. Les compteurs Collection/Wantlist et les "derniers ajouts" sont 3
    /// appels légers mais, derrière un quota Discogs bas, `DiscogsRateLimiter` peut espacer chacun
    /// de 2 à 10s — ils n'alimentent que `countersRow`/`recentAdditionsSection`, qui savent déjà
    /// s'afficher sans leur donnée ("–", section absente), donc plus question qu'ils retiennent
    /// tout l'écran derrière le squelette pendant qu'ils répondent.
    func loadOverview() async {
        guard let username = authManager.username else { return }

        // Charge le cache local pérenne des MasterRecords (avant les calculs qui en dépendent)
        masterYearsResolver.reloadKnownYears()

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

        // Compteurs et valeur : redemandés à Discogs au plus toutes les 5 min (voir
        // `ReloadThrottle`), au lieu de 4 requêtes à chaque visite de l'onglet.
        if NetworkMonitor.shared.isConnected, collectionValue == nil || overviewThrottle.shouldReload(for: username) {
            overviewThrottle.recordReload(for: username)
            async let counters: Void = loadCounters(username: username)
            async let valuation: Void = loadValuation()
            async let invested: Void = computeTotalInvestedIfNeeded()
            _ = await (counters, valuation, invested)
        } else {
            await computeTotalInvestedIfNeeded()
        }
    }

    /// Compteurs Collection/Wantlist + derniers ajouts : 3 appels légers (`per_page` réduit),
    /// indépendants du reste de l'écran (voir `loadOverview`).
    private func loadCounters(username: String) async {
        isLoadingCounters = true
        defer { isLoadingCounters = false }
        guard let credentials = authManager.credentials else { return }
        do {
            let counters = try await StatsDataService.fetchCounters(username: username, credentials: credentials)
            guard authManager.username == username else { return }
            totalCollectionCount = counters.collectionCount
            totalWantlistCount = counters.wantlistCount
            // Même animation que les autres sections de l'écran (répartitions, classements…) au
            // passage du squelette aux vraies pochettes, plutôt qu'un remplacement instantané.
            withAnimation(.statsContentChange) {
                recentAdditions = counters.recentAdditions.filter { !locallyRemovedInstanceIds.contains($0.instanceId) }
            }
        } catch {
            // Sans réseau (ou erreur transitoire) : repli sur le cache local pour les compteurs ;
            // seuls les « derniers ajouts » restent vides.
            let cached = await StatsDataService.cachedCounts(username: username)
            guard authManager.username == username else { return }
            if let collection = cached.collection { totalCollectionCount = collection }
            if let wantlist = cached.wantlist { totalWantlistCount = wantlist }
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
        // if let collectionValue { StatsDataService.recordCollectionSnapshotIfNeeded(collectionValue, username: username) }
        refreshValueHistoryFromLocalStore()
    }

    /// Somme les prix d'achat renseignés sur la collection (déjà chargée en cache), convertis
    /// vers la devise par défaut de l'utilisateur, pour le bilan "Total investi vs Cote actuelle".
    func computeTotalInvestedIfNeeded() async {
        guard let username = authManager.username,
              CollectionPreferencesStore.purchasePriceFieldId(for: username) != nil else { return }
        isComputingInvested = true
        defer { isComputingInvested = false }
        guard let result = await StatsDataService.totalInvested(of: allCollectionItems, username: username),
              authManager.username == username else { return }
        totalInvested = result.total
        totalInvestedCurrency = result.currency
    }

    /// Remplace la collection analysée et recalcule toutes les répartitions qui en dépendent.
    private func applyCollectionItems(_ items: [CollectionItem]) {
        allCollectionItems = items
        additionsPerYear = Self.groupByYear(items)
        masterYearsResolver.update(for: items)
        applyDistributions()
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
                    // Annulée ou compte changé pendant le chargement (déconnexion, sortie de démo) :
                    // ces disques ne doivent ni s'afficher ni réécrire le cache d'un autre compte.
                    guard !Task.isCancelled, self.authManager.username == username else { return }
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

    // MARK: - Répartitions (genres, labels, supports, artistes)

    /// Recalcule toutes les répartitions de la collection (voir `StatsDistributions`), appliquées
    /// ensemble avec la même animation.
    private func applyDistributions() {
        let genres = Self.genreDistribution(of: allCollectionItems)
        let labels = Self.labelDistribution(of: allCollectionItems)
        let media = Self.mediaFormatDistribution(of: allCollectionItems)
        let artists = Self.artistRanking(of: allCollectionItems)
        withAnimation(.statsContentChange) {
            otherGenresNames = genres.others
            genreDistribution = genres.entries
            otherLabelsNames = labels.others
            labelDistribution = labels.entries
            mediaFormatDistribution = media.formats
            vinylSizeBreakdown = media.vinylSizes
            topArtistsByCollectionCount = artists
        }
    }

    /// Retourne la liste des disques correspondant à un label donné.
    func items(forLabel labelName: String) -> [CollectionItem] {
        Self.sortedByTitle(Self.items(withLabel: labelName, in: allCollectionItems, otherLabels: otherLabelsNames))
    }

    /// Retourne la liste des disques appartenant à un support donné ("Vinyles", "CD"...).
    func items(forMediaFormat name: String) -> [CollectionItem] {
        Self.sortedByTitle(allCollectionItems.filter { Release(from: $0).shelfMediaCategory.broadFormatLabel == name })
    }

    /// Retourne la liste des disques d'une taille de vinyle précise (détail au tap de "Vinyles").
    func items(forShelfCategory category: ShelfMediaCategory) -> [CollectionItem] {
        Self.sortedByTitle(allCollectionItems.filter { Release(from: $0).shelfMediaCategory == category })
    }

    /// Retourne la liste des disques correspondant à un genre donné.
    func items(forGenre genreName: String) -> [CollectionItem] {
        Self.sortedByTitle(Self.items(withGenre: genreName, in: allCollectionItems, otherGenres: otherGenresNames))
    }

    /// Détail des styles musicaux parmi les disques d'un genre donné, triés par nombre
    /// d'occurrences (les 6 styles majeurs). Un disque ayant plusieurs styles compte pour
    /// chacun d'eux, donc la somme des occurrences peut dépasser le nombre de disques du genre.
    func styleBreakdown(forGenre genreName: String) -> [StyleBreakdownEntry] {
        // Lus même quand le cache répond, pour que la vue reste invalidée par leurs changements
        // (le cache lui-même n'est pas observé).
        _ = allCollectionItems
        _ = otherGenresNames
        if let cached = styleBreakdownCache[genreName] { return cached }
        let result = Self.styleBreakdown(of: Self.items(withGenre: genreName, in: allCollectionItems, otherGenres: otherGenresNames))
        styleBreakdownCache[genreName] = result
        return result
    }

    /// Retourne la liste des disques d'un genre donné qui portent aussi un style précis
    /// (détail affiché au tap d'un style dans `styleBreakdown`).
    func items(forGenre genreName: String, style styleName: String) -> [CollectionItem] {
        items(forGenre: genreName).filter { $0.basicInformation.styles?.contains(styleName) == true }
    }

    /// Répartition de `originalYearsDistribution` regroupée par décennie (1990 → 1990-1999),
    /// pour une vue moins dense sur une grande collection. Triée par décennies décroissantes.
    var originalYearsDistributionByDecade: [(decade: Int, count: Int)] {
        Self.decades(of: originalYearsDistribution)
    }

    // MARK: - Listes de disques des histogrammes et du classement des artistes

    /// Filtre et tri de toute la collection, calculés hors du fil principal pour ne pas retarder
    /// l'affichage de la sélection au toucher d'une barre. Pas de repli réseau ou cache si la
    /// collection est encore vide : ces listes ne s'ouvrent que depuis un graphique déjà rempli.
    private func detachedItems(
        _ select: @escaping @Sendable (_ items: [CollectionItem], _ masterYears: [Int: Int]) -> [CollectionItem]
    ) async -> [CollectionItem] {
        let source = allCollectionItems
        let masterYears = masterYearsResolver.masterYears
        return await Task.detached(priority: .userInitiated) { select(source, masterYears) }.value
    }

    /// Disques d'un artiste (même regroupement que le classement, suffixe d'homonymie ignoré).
    func items(forArtist artistName: String) async -> [CollectionItem] {
        await detachedItems { items, _ in
            Self.sortedByTitle(items.filter { ArtistShelfSortHelper.cleanDiscogsSuffix($0.basicInformation.artistNames) == artistName })
        }
    }

    /// Disques sortis à une année originale donnée.
    func items(forOriginalYear year: Int) async -> [CollectionItem] {
        await detachedItems { items, masterYears in
            Self.sortedByTitle(items.filter { Self.resolvedOriginalYear(for: $0, masterYears: masterYears) == year })
        }
    }

    /// Disques sortis durant une décennie donnée (ex. 1990 → 1990-1999).
    func items(forOriginalDecade decade: Int) async -> [CollectionItem] {
        await detachedItems { items, masterYears in
            Self.sortedByTitle(items.filter { item in
                guard let year = Self.resolvedOriginalYear(for: item, masterYears: masterYears) else { return false }
                return year >= decade && year < decade + 10
            })
        }
    }

    /// Disques ajoutés durant une année donnée, du plus récent au plus ancien.
    func items(forYear year: Int) async -> [CollectionItem] {
        await detachedItems { items, _ in Self.itemsAdded(in: year, from: items) }
    }

    // MARK: - Tops & Palmarès d'écoute (fonctionnalité premium)

    private let listeningStore = ListeningLogStore.shared

    /// Classement des releases les plus écoutées de la collection, du plus au moins écouté.
    /// Vide tant que le nombre total d'écoutes enregistrées est trop faible pour être pertinent.
    /// Recalculé par `recomputeListeningStats()` plutôt qu'à chaque lecture (voir son commentaire).
    private(set) var topAlbums: [TopAlbumEntry] = []

    /// Classement des artistes dont les disques cumulent le plus d'écoutes, tous exemplaires
    /// confondus (ex. "Miles Davis : 27 sessions réparties sur 3 disques").
    private(set) var topArtists: [TopArtistEntry] = []

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
        let rankings = Self.listeningRankings(sessions: listeningStore.sessions, releases: releaseById)
        topAlbums = rankings.topAlbums
        topArtists = rankings.topArtists
        monthlyPodium = rankings.monthlyPodium
        yearlyPodium = rankings.yearlyPodium
    }
}
