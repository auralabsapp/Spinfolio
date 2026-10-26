import Foundation

/// Liste triée des tags et nombre d'exemplaires qui portent chacun d'eux, calculés en un seul
/// parcours. Mis en cache par `TagStore` ; fonction pure pour pouvoir la tester sans le store.
nonisolated struct TagSummary: Equatable {
    /// Tous les tags (exemplaires, anciens tags par release, tags autonomes), triés alphabétiquement.
    let allTags: [String]
    private let instanceCounts: [String: Int]
    private let legacyCounts: [String: Int]

    /// - Parameters:
    ///   - instanceTags: noms des tags de chaque exemplaire ;
    ///   - legacyTags: noms des tags de chaque release (ancien stockage par `releaseId`) ;
    ///   - standaloneTags: tags créés sans être appliqués.
    init(instanceTags: [[String]], legacyTags: [[String]], standaloneTags: Set<String>) {
        instanceCounts = Self.countPerTag(instanceTags)
        legacyCounts = Self.countPerTag(legacyTags)
        allTags = Set(instanceCounts.keys).union(legacyCounts.keys).union(standaloneTags)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Nombre d'exemplaires portant ce tag ; à défaut, nombre de releases de l'ancien stockage
    /// (même règle qu'avant le cache).
    func count(for tag: String) -> Int {
        if let count = instanceCounts[tag], count > 0 { return count }
        return legacyCounts[tag] ?? 0
    }

    /// Un exemplaire compte une seule fois par tag, même si son tableau contient un doublon.
    private static func countPerTag(_ lists: [[String]]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for names in lists {
            for name in Set(names) {
                counts[name, default: 0] += 1
            }
        }
        return counts
    }
}
