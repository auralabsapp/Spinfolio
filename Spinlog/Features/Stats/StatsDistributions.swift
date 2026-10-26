import Foundation

/// Répartitions de la collection affichées dans Stats (genres, labels, supports, artistes),
/// calculées par des fonctions pures sur la liste des disques : `StatsViewModel` ne fait plus
/// que les appliquer (avec animation). Testées dans `StatsCalculationTests`.
extension StatsViewModel {
    /// Part d'un camembert : nom, nombre d'occurrences et pourcentage du total.
    struct DistributionSlice: Equatable {
        let name: String
        let count: Int
        let percentage: Double
    }

    /// Les `maxSlices` parts majeures (par nombre décroissant, puis par nom), les suivantes étant
    /// regroupées en une dernière part « Autres » quand il y en a plus de `maxSlices`.
    static func topSlices(_ counts: [String: Int], maxSlices: Int = 6) -> (slices: [DistributionSlice], others: Set<String>) {
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return ([], []) }

        let sorted = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        var slices: [DistributionSlice] = []
        var othersCount = 0
        var others = Set<String>()

        for (index, pair) in sorted.enumerated() {
            if sorted.count > maxSlices && index >= maxSlices - 1 {
                othersCount += pair.value
                others.insert(pair.key)
            } else {
                slices.append(DistributionSlice(name: pair.key, count: pair.value, percentage: Double(pair.value) / Double(total) * 100))
            }
        }
        if othersCount > 0 {
            slices.append(DistributionSlice(name: othersLabel, count: othersCount, percentage: Double(othersCount) / Double(total) * 100))
        }
        return (slices, others)
    }

    /// Répartition par genre ; un disque sans genre compte en « Non spécifié ».
    static func genreDistribution(of items: [CollectionItem]) -> (entries: [GenreDistributionEntry], others: Set<String>) {
        var counts: [String: Int] = [:]
        for item in items {
            let genres = item.basicInformation.genres?
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty } ?? []
            if genres.isEmpty {
                counts[unspecifiedLabel, default: 0] += 1
            } else {
                for genre in genres { counts[genre, default: 0] += 1 }
            }
        }
        let (slices, others) = topSlices(counts)
        return (slices.map { GenreDistributionEntry(name: $0.name, count: $0.count, percentage: $0.percentage) }, others)
    }

    /// Répartition par label (maison de disques), même règle que les genres.
    static func labelDistribution(of items: [CollectionItem]) -> (entries: [LabelDistributionEntry], others: Set<String>) {
        var counts: [String: Int] = [:]
        for item in items {
            let labels = item.basicInformation.labels?
                .map { $0.name.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty } ?? []
            if labels.isEmpty {
                counts[unspecifiedLabel, default: 0] += 1
            } else {
                for label in labels { counts[label, default: 0] += 1 }
            }
        }
        let (slices, others) = topSlices(counts)
        return (slices.map { LabelDistributionEntry(name: $0.name, count: $0.count, percentage: $0.percentage) }, others)
    }

    /// Répartition Vinyles/CD/Cassettes/Autres, dans cet ordre fixe (pas par volume), et détail
    /// par taille au sein des vinyles (12"/10"/7"), d'après le format Discogs principal.
    static func mediaFormatDistribution(of items: [CollectionItem]) -> (formats: [MediaFormatDistributionEntry], vinylSizes: [VinylSizeBreakdownEntry]) {
        var broadCounts: [String: Int] = [:]
        var vinylSizeCounts: [ShelfMediaCategory: Int] = [:]
        for item in items {
            let category = Release(from: item).shelfMediaCategory
            broadCounts[category.broadFormatLabel, default: 0] += 1
            if category == .vinyl12 || category == .vinyl10 || category == .vinyl7 {
                vinylSizeCounts[category, default: 0] += 1
            }
        }

        let total = broadCounts.values.reduce(0, +)
        guard total > 0 else { return ([], []) }

        let order = [ShelfMediaCategory.vinyl12, .cd, .cassette, .other].map(\.broadFormatLabel)
        let formats = order.compactMap { label -> MediaFormatDistributionEntry? in
            guard let count = broadCounts[label], count > 0 else { return nil }
            return MediaFormatDistributionEntry(name: label, count: count, percentage: Double(count) / Double(total) * 100)
        }
        let sizes = [ShelfMediaCategory.vinyl12, .vinyl10, .vinyl7].compactMap { category -> VinylSizeBreakdownEntry? in
            guard let count = vinylSizeCounts[category], count > 0 else { return nil }
            return VinylSizeBreakdownEntry(category: category, count: count)
        }
        return (formats, sizes)
    }

    /// Classement complet des artistes par nombre de disques possédés, regroupés comme dans le
    /// classement d'écoute (suffixe d'homonymie Discogs « (2) » ignoré).
    static func artistRanking(of items: [CollectionItem]) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in items {
            let name = ArtistShelfSortHelper.cleanDiscogsSuffix(item.basicInformation.artistNames)
            guard !name.isEmpty else { continue }
            counts[name, default: 0] += 1
        }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (name: $0.key, count: $0.value) }
    }
}
