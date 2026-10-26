import Foundation

/// Disques d'une part de répartition (genre, label) et détail par style, pour les feuilles de
/// l'onglet Stats. Fonctions pures, testées dans `StatsCalculationTests`.
extension StatsViewModel {
    /// Disques d'un genre : « Autres » regroupe les genres hors des parts principales, « Non
    /// spécifié » les disques sans genre. Non triés (le tri par titre est fait à l'affichage).
    static func items(withGenre genre: String, in items: [CollectionItem], otherGenres: Set<String>) -> [CollectionItem] {
        if genre == othersLabel {
            return items.filter { ($0.basicInformation.genres ?? []).contains { otherGenres.contains($0) } }
        } else if genre == unspecifiedLabel {
            return items.filter { item in
                (item.basicInformation.genres ?? []).allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            }
        }
        return items.filter { $0.basicInformation.genres?.contains(genre) == true }
    }

    /// Disques d'un label, même règle que les genres pour « Autres » et « Non spécifié ».
    static func items(withLabel label: String, in items: [CollectionItem], otherLabels: Set<String>) -> [CollectionItem] {
        if label == othersLabel {
            return items.filter { ($0.basicInformation.labels?.map(\.name) ?? []).contains { otherLabels.contains($0) } }
        } else if label == unspecifiedLabel {
            return items.filter { item in
                (item.basicInformation.labels ?? []).allSatisfy { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            }
        }
        return items.filter { $0.basicInformation.labels?.contains { $0.name == label } == true }
    }

    /// Les 6 styles les plus présents parmi ces disques (par nombre décroissant, puis par nom). Un
    /// disque à plusieurs styles compte pour chacun : la somme peut dépasser le nombre de disques.
    static func styleBreakdown(of items: [CollectionItem]) -> [StyleBreakdownEntry] {
        var counts: [String: Int] = [:]
        for item in items {
            for style in item.basicInformation.styles ?? [] {
                let clean = style.trimmingCharacters(in: .whitespaces)
                guard !clean.isEmpty else { continue }
                counts[clean, default: 0] += 1
            }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(6)
            .map { StyleBreakdownEntry(name: $0.key, count: $0.value) }
    }
}
