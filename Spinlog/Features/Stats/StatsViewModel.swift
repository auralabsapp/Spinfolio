import Foundation
import Observation
import SwiftUI

/// Une release de la collection classée par nombre d'écoutes enregistrées.
struct TopAlbumEntry: Identifiable {
    let item: CollectionItem
    let playCount: Int
    var id: Int { item.releaseId }
}

/// Un artiste classé par nombre total d'écoutes cumulées sur tous ses disques possédés.
/// Entrée de la répartition par genre musical.
struct GenreDistributionEntry: Identifiable, Equatable {
    let name: String
    let count: Int
    let percentage: Double
    var id: String { name }
}

/// Détail par style musical au sein d'un genre sélectionné (affiché au tap d'une part du
/// camembert des genres). Pas de pourcentage : un disque a souvent plusieurs styles à la fois,
/// donc ce classement ne se totalise pas à 100 % comme le camembert des genres.
struct StyleBreakdownEntry: Identifiable, Equatable {
    let name: String
    let count: Int
    var id: String { name }
}

/// Entrée de la répartition par label (maison de disques).
struct LabelDistributionEntry: Identifiable, Equatable {
    let name: String
    let count: Int
    let percentage: Double
    var id: String { name }
}

/// Entrée de la répartition par support physique (Vinyles/CD/Cassettes/Autres).
struct MediaFormatDistributionEntry: Identifiable, Equatable {
    let name: String
    let count: Int
    let percentage: Double
    var id: String { name }
}

/// Détail par taille au sein de la part "Vinyles" (12"/10"/7"), affiché au tap de cette part.
struct VinylSizeBreakdownEntry: Identifiable, Equatable {
    let category: ShelfMediaCategory
    let count: Int
    var id: String { category.rawValue }
    var label: String { category.shortSizeLabel }
}

struct TopArtistEntry: Identifiable {
    let name: String
    let totalPlays: Int
    let releaseCount: Int
    var id: String { name }
}

@Observable
@MainActor
final class StatsViewModel {
    /// En dessous de ce nombre d'écoutes enregistrées, un classement n'est pas jugé assez
    /// représentatif pour être affiché (trop peu de données pour être pertinent).
    static let minimumListeningSessionsForRanking = 5
    private(set) var isLoadingOverview = false

    private(set) var totalCollectionCount: Int?
    private(set) var totalWantlistCount: Int?
    private(set) var recentAdditions: [CollectionItem] = []
    private(set) var allCollectionItems: [CollectionItem] = []

    /// Nombre d'artistes distincts dans la collection, regroupés comme dans le classement
    /// "Top Artistes" (le suffixe de désambiguïsation Discogs, ex. « Artist (2) », est ignoré).
    var uniqueArtistsCount: Int? {
        guard !allCollectionItems.isEmpty else { return nil }
        let names = allCollectionItems
            .map { ArtistShelfSortHelper.cleanDiscogsSuffix($0.basicInformation.artistNames) }
            .filter { !$0.isEmpty }
        return Set(names).count
    }

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
        valueHistoryPoints = localStore.allCollectionSnapshots().map { ($0.date, $0.low, $0.median, $0.high) }
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

    /// Compteurs + derniers ajouts : chacun est un seul appel léger (`per_page` réduit).
    func loadOverview() async {
        guard let (username, credentials) = authManager.session else { return }
        isLoadingOverview = true
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
            recentAdditions = recentResponse.releases
        } catch {
            // Sans réseau (ou erreur transitoire), on retombe sur le cache local pour les 2
            // compteurs qui ont un équivalent exact (contrairement à la cote de marché, qui
            // n'en a aucun) : seuls les "derniers ajouts" restent vides. Si même ce cache est
            // vide (jamais synchronisé), on laisse le compteur à `nil` plutôt que d'afficher un
            // 0 trompeur — `countersRow` affiche alors "–".
            let cachedCollection = localStore.getCollectionItems(username: username, folderId: DiscogsConstants.allFolderId)
            let cachedWantlist = localStore.getWantlistItems(username: username)
            if !cachedCollection.isEmpty {
                totalCollectionCount = cachedCollection.count
            }
            if !cachedWantlist.isEmpty {
                totalWantlistCount = cachedWantlist.count
            }
        }
        isLoadingOverview = false

        if let username = authManager.username {
            let cached = localStore.getCollectionItems(username: username, folderId: DiscogsConstants.allFolderId)
            if !cached.isEmpty {
                allCollectionItems = cached
                updateGenreDistribution()
                updateLabelDistribution()
                updateMediaFormatDistribution()
                updateTopArtistsByCollectionCount()
            }
        }

        // Charge le cache local pérenne des MasterRecords
        masterYearsCache = localStore.getAllMasterYears()

        startHistogramLoad()
        await loadValuation()
        await computeTotalInvestedIfNeeded()
    }

    private func loadValuation() async {
        guard let (username, credentials) = authManager.session else { return }
        isLoadingValuation = true
        collectionValue = try? await DiscogsAPIClient.shared.collectionValue(username: username, credentials: credentials)
        isLoadingValuation = false
        recordCollectionSnapshotIfNeeded()
        valueHistoryPoints = localStore.allCollectionSnapshots().map { ($0.date, $0.low, $0.median, $0.high) }
    }

    /// Enregistre un nouveau point d'historique (au plus 1 par jour) à partir de la valeur de
    /// collection déjà chargée. `CollectionValueResponse` renvoie des montants déjà formatés par
    /// Discogs (ex. `"$960.00"`) : on les reparse pour en tirer des nombres exploitables en graphique.
    private func recordCollectionSnapshotIfNeeded() {
        guard let collectionValue else { return }
        let oneDay: TimeInterval = DiscogsConstants.oneDayTTL
        if let latest = localStore.latestCollectionSnapshot(), Date().timeIntervalSince(latest.date) < oneDay {
            return
        }
        guard let low = PurchasePriceParser.parseFormattedDiscogsAmount(collectionValue.minimum),
              let median = PurchasePriceParser.parseFormattedDiscogsAmount(collectionValue.median),
              let high = PurchasePriceParser.parseFormattedDiscogsAmount(collectionValue.maximum) else { return }
        localStore.saveCollectionSnapshot(currency: median.currency, low: low.amount, median: median.amount, high: high.amount)
    }

    /// Somme les prix d'achat renseignés sur la collection (déjà chargée en cache), convertis
    /// vers la devise par défaut de l'utilisateur, pour le bilan "Total investi vs Cote actuelle".
    func computeTotalInvestedIfNeeded() async {
        guard let username = authManager.username,
              let fieldId = CollectionPreferencesStore.purchasePriceFieldId(for: username) else { return }
        let currency = CollectionPreferencesStore.defaultCurrency(for: username)

        isComputingInvested = true
        var total = 0.0
        for item in allCollectionItems {
            let raw = item.value(forFieldId: fieldId).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, let parsed = PurchasePriceParser.parse(raw, defaultCurrency: currency) else { continue }
            total += await CurrencyConversionService.shared.convert(parsed.amount, from: parsed.currency, to: currency)
        }
        totalInvested = total
        totalInvestedCurrency = currency
        isComputingInvested = false
    }

    /// Regroupe les dates d'ajout par année et lance le calcul des années originales.
    private func startHistogramLoad() {
        histogramTask?.cancel()
        guard let username = authManager.username else { return }

        if !localStore.isCollectionStale(username: username, folderId: DiscogsConstants.allFolderId) {
            let cached = localStore.getCollectionItems(username: username, folderId: DiscogsConstants.allFolderId)
            if !cached.isEmpty {
                allCollectionItems = cached
                additionsPerYear = Self.groupByYear(cached)
                updateOriginalYearsDistribution()
                updateGenreDistribution()
                updateLabelDistribution()
                updateMediaFormatDistribution()
                updateTopArtistsByCollectionCount()
                return
            }
        }

        guard let credentials = authManager.credentials else { return }
        isLoadingHistogram = true
        histogramTask = Task { [weak self] in
            guard let self else { return }
            do {
                let allItems = try await DiscogsAPIClient.shared.fetchAllCollectionItems(
                    username: username, folderId: DiscogsConstants.allFolderId, credentials: credentials
                )
                guard !Task.isCancelled else { return }
                self.allCollectionItems = allItems
                self.totalCollectionCount = allItems.count
                self.additionsPerYear = Self.groupByYear(allItems)
                self.localStore.syncCollectionFolder(username: username, folderId: DiscogsConstants.allFolderId, fullItems: allItems)
                self.updateOriginalYearsDistribution()
                self.updateGenreDistribution()
                self.updateLabelDistribution()
                self.updateMediaFormatDistribution()
                self.updateTopArtistsByCollectionCount()
            } catch {
                // On garde l'histogramme vide en cas d'échec.
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
                counts["Non spécifié", default: 0] += 1
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
            entries.append(GenreDistributionEntry(name: "Autres", count: othersCount, percentage: pct))
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
                counts["Non spécifié", default: 0] += 1
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
            entries.append(LabelDistributionEntry(name: "Autres", count: othersCount, percentage: pct))
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            self.otherLabelsNames = othersSet
            self.labelDistribution = entries
        }
    }

    /// Retourne la liste des disques correspondant à un label donné.
    func items(forLabel labelName: String) -> [CollectionItem] {
        if labelName == "Autres" {
            return allCollectionItems.filter { item in
                let labels = item.basicInformation.labels?.map(\.name) ?? []
                return labels.contains { otherLabelsNames.contains($0) }
            }.sorted { item1, item2 in
                item1.basicInformation.title.localizedStandardCompare(item2.basicInformation.title) == .orderedAscending
            }
        } else if labelName == "Non spécifié" {
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
        let order = ["Vinyles", "CD", "Cassettes", "Autres"]
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
        if genreName == "Autres" {
            return allCollectionItems.filter { item in
                let genres = item.basicInformation.genres ?? []
                return genres.contains { otherGenresNames.contains($0) }
            }.sorted { item1, item2 in
                item1.basicInformation.title.localizedStandardCompare(item2.basicInformation.title) == .orderedAscending
            }
        } else if genreName == "Non spécifié" {
            return allCollectionItems.filter { item in
                let genres = item.basicInformation.genres?.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? []
                return genres.isEmpty
            }.sorted { item1, item2 in
                item1.basicInformation.title.localizedStandardCompare(item2.basicInformation.title) == .orderedAscending
            }
        } else {
            return allCollectionItems.filter { item in
                item.basicInformation.genres?.contains(genreName) == true
            }.sorted { item1, item2 in
                item1.basicInformation.title.localizedStandardCompare(item2.basicInformation.title) == .orderedAscending
            }
        }
    }

    /// Détail des styles musicaux parmi les disques d'un genre donné, triés par nombre
    /// d'occurrences (les 6 styles majeurs). Un disque ayant plusieurs styles compte pour
    /// chacun d'eux, donc la somme des occurrences peut dépasser le nombre de disques du genre.
    func styleBreakdown(forGenre genreName: String) -> [StyleBreakdownEntry] {
        var counts: [String: Int] = [:]
        for item in items(forGenre: genreName) {
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
    func items(forArtist artistName: String) -> [CollectionItem] {
        allCollectionItems.filter {
            ArtistShelfSortHelper.cleanDiscogsSuffix($0.basicInformation.artistNames) == artistName
        }.sorted { item1, item2 in
            item1.basicInformation.title.localizedStandardCompare(item2.basicInformation.title) == .orderedAscending
        }
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
            await MasterResolutionService.shared.resolveMasters(missingMasterIds: missingList) { [weak self] resolved, total, masterId, year in
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
    private func resolvedOriginalYear(for item: CollectionItem) -> Int? {
        if let masterId = item.basicInformation.masterId, masterId > 0, let cachedYear = masterYearsCache[masterId], cachedYear > 0 {
            return cachedYear
        } else if let releaseYear = item.basicInformation.year, releaseYear > 0 {
            return releaseYear
        }
        return nil
    }

    /// Retourne la liste des disques de la collection sortis à une année originale donnée.
    func items(forOriginalYear year: Int) -> [CollectionItem] {
        allCollectionItems.filter { resolvedOriginalYear(for: $0) == year }
            .sorted { item1, item2 in
                item1.basicInformation.title.localizedStandardCompare(item2.basicInformation.title) == .orderedAscending
            }
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
    func items(forOriginalDecade decade: Int) -> [CollectionItem] {
        allCollectionItems.filter { item in
            guard let year = resolvedOriginalYear(for: item) else { return false }
            return year >= decade && year < decade + 10
        }.sorted { item1, item2 in
            item1.basicInformation.title.localizedStandardCompare(item2.basicInformation.title) == .orderedAscending
        }
    }

    /// Retourne la liste des disques de la collection ajoutés durant une année donnée,
    /// triés du plus récent au plus ancien par date d'ajout.
    func items(forYear year: Int) -> [CollectionItem] {
        let source: [CollectionItem]
        if !allCollectionItems.isEmpty {
            source = allCollectionItems
        } else if let username = authManager.username {
            source = localStore.getCollectionItems(username: username, folderId: DiscogsConstants.allFolderId)
        } else {
            source = []
        }
        return source.filter { item in
            guard let date = item.dateAddedDate else { return false }
            return Calendar.current.component(.year, from: date) == year
        }.sorted { item1, item2 in
            let d1 = item1.dateAddedDate ?? .distantPast
            let d2 = item2.dateAddedDate ?? .distantPast
            if d1 != d2 { return d1 > d2 }
            return item1.basicInformation.title.localizedStandardCompare(item2.basicInformation.title) == .orderedAscending
        }
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

    /// Une release par `releaseId` (peu importe l'exemplaire) pour retrouver titre/artiste/pochette
    /// à partir d'une session d'écoute, qui ne connaît que le `releaseId`.
    private var releaseById: [Int: CollectionItem] {
        var result: [Int: CollectionItem] = [:]
        for item in allCollectionItems where result[item.releaseId] == nil {
            result[item.releaseId] = item
        }
        return result
    }

    var totalListeningSessionsCount: Int {
        listeningStore.sessions.count
    }

    /// Classement des releases les plus écoutées de la collection, du plus au moins écouté.
    /// Vide tant que le nombre total d'écoutes enregistrées est trop faible pour être pertinent.
    var topAlbums: [TopAlbumEntry] {
        guard totalListeningSessionsCount >= Self.minimumListeningSessionsForRanking else { return [] }
        return rankedAlbums(sessions: listeningStore.sessions)
    }

    /// Classement des artistes dont les disques cumulent le plus d'écoutes, tous exemplaires
    /// confondus (ex. "Miles Davis : 27 sessions réparties sur 3 disques").
    var topArtists: [TopArtistEntry] {
        guard totalListeningSessionsCount >= Self.minimumListeningSessionsForRanking else { return [] }
        let releases = releaseById
        var playsByArtist: [String: Int] = [:]
        var releasesByArtist: [String: Set<Int>] = [:]

        for session in listeningStore.sessions {
            guard let item = releases[session.releaseId] else { continue }
            let artist = ArtistShelfSortHelper.cleanDiscogsSuffix(item.basicInformation.artistNames)
            guard !artist.isEmpty else { continue }
            playsByArtist[artist, default: 0] += 1
            releasesByArtist[artist, default: []].insert(session.releaseId)
        }

        return playsByArtist.map { name, totalPlays in
            TopArtistEntry(name: name, totalPlays: totalPlays, releaseCount: releasesByArtist[name]?.count ?? 0)
        }
        .sorted { $0.totalPlays != $1.totalPlays ? $0.totalPlays > $1.totalPlays : $0.name < $1.name }
    }

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
    var monthlyPodium: [TopAlbumEntry] {
        guard monthlyListeningSessionsCount >= Self.minimumListeningSessionsForRanking,
              let startOfMonth = Self.startOfCurrentMonth else { return [] }
        let sessionsThisMonth = listeningStore.sessions.filter { $0.timestamp >= startOfMonth }
        return Array(rankedAlbums(sessions: sessionsThisMonth).prefix(3))
    }

    /// Podium (top 3) des albums les plus écoutés depuis le début de l'année : les classiques
    /// intemporels de la collection, ceux qui reviennent toute l'année.
    var yearlyPodium: [TopAlbumEntry] {
        guard yearlyListeningSessionsCount >= Self.minimumListeningSessionsForRanking,
              let startOfYear = Self.startOfCurrentYear else { return [] }
        let sessionsThisYear = listeningStore.sessions.filter { $0.timestamp >= startOfYear }
        return Array(rankedAlbums(sessions: sessionsThisYear).prefix(3))
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
