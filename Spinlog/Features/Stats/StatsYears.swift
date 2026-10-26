import Foundation

/// Années de l'onglet Stats : année originale de chaque disque (année du master si elle est
/// connue, sinon année de pressage), répartitions par année et par décennie, avancement de la
/// résolution des masters, et années d'ajout. Fonctions pures, testées dans `StatsCalculationTests`.
extension StatsViewModel {
    /// Année originale d'un exemplaire : année du master si connue, sinon année de pressage.
    nonisolated static func resolvedOriginalYear(for item: CollectionItem, masterYears: [Int: Int]) -> Int? {
        if let masterId = item.basicInformation.masterId, masterId > 0, let cachedYear = masterYears[masterId], cachedYear > 0 {
            return cachedYear
        } else if let releaseYear = item.basicInformation.year, releaseYear > 0 {
            return releaseYear
        }
        return nil
    }

    /// Nombre de disques par année originale, des plus récentes aux plus anciennes. Les années
    /// improbables (avant 1901 ou dans le futur) sont écartées.
    static func originalYears(of items: [CollectionItem], masterYears: [Int: Int], now: Date = Date()) -> [(year: Int, count: Int)] {
        let currentYear = Calendar.current.component(.year, from: now)
        var counts: [Int: Int] = [:]
        for item in items {
            if let year = resolvedOriginalYear(for: item, masterYears: masterYears), year > 1900, year <= currentYear {
                counts[year, default: 0] += 1
            }
        }
        return counts.sorted { $0.key > $1.key }.map { (year: $0.key, count: $0.value) }
    }

    /// Répartition par années regroupée par décennie (1990 → 1990-1999), décennies décroissantes.
    static func decades(of distribution: [(year: Int, count: Int)]) -> [(decade: Int, count: Int)] {
        var counts: [Int: Int] = [:]
        for entry in distribution {
            counts[(entry.year / 10) * 10, default: 0] += entry.count
        }
        return counts.sorted { $0.key > $1.key }.map { (decade: $0.key, count: $0.value) }
    }

    /// Masters dont l'année n'est pas encore connue.
    static func missingMasterIds(in items: [CollectionItem], masterYears: [Int: Int]) -> Set<Int> {
        var missing = Set<Int>()
        for item in items {
            if let masterId = item.basicInformation.masterId, masterId > 0, masterYears[masterId] == nil {
                missing.insert(masterId)
            }
        }
        return missing
    }

    /// Part des disques dont l'année originale est connue (année du master en cache, ou disque
    /// sans master qui prend son année de pressage), entre 0 et 1 ; 1 pour une collection vide.
    static func masterResolutionProgress(of items: [CollectionItem], masterYears: [Int: Int]) -> Double {
        guard !items.isEmpty else { return 1.0 }
        let resolved = items.filter { item in
            guard let masterId = item.basicInformation.masterId, masterId > 0 else { return true }
            return masterYears[masterId] != nil
        }.count
        return min(1.0, max(0.0, Double(resolved) / Double(items.count)))
    }

    nonisolated static func sortedByTitle(_ items: [CollectionItem]) -> [CollectionItem] {
        items.sorted { item1, item2 in
            item1.basicInformation.title.localizedStandardCompare(item2.basicInformation.title) == .orderedAscending
        }
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
    static func groupByYear(_ items: [CollectionItem]) -> [(year: Int, count: Int)] {
        var counts: [Int: Int] = [:]
        for item in items {
            guard let date = item.dateAddedDate else { continue }
            let year = Calendar.current.component(.year, from: date)
            counts[year, default: 0] += 1
        }
        return counts.sorted { $0.key > $1.key }.map { (year: $0.key, count: $0.value) }
    }
}
