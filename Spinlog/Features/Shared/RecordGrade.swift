import Foundation

/// État d'un disque (grille Goldmine reprise par Discogs). Les valeurs brutes sont les libellés
/// exacts des options du champ « Media Condition » de Discogs : l'import, la synchro vers Discogs
/// et la cote par état (`MarketEstimateService`) s'en servent sans table de conversion. Les libellés
/// restent en anglais, comme les autres noms Discogs de l'app.
nonisolated enum RecordGrade: String, CaseIterable, Codable, Sendable, Identifiable {
    case mint = "Mint (M)"
    case nearMint = "Near Mint (NM or M-)"
    case veryGoodPlus = "Very Good Plus (VG+)"
    case veryGood = "Very Good (VG)"
    case goodPlus = "Good Plus (G+)"
    case good = "Good (G)"
    case fair = "Fair (F)"
    case poor = "Poor (P)"

    var id: String { rawValue }

    /// Libellé tel qu'il est écrit sur Discogs.
    var discogsLabel: String { rawValue }

    /// Écritures acceptées pour retrouver un grade dans une valeur lue ailleurs : libellé complet,
    /// nom sans le code, ou code seul. Comparées sans casse ni espaces superflus. Une écriture qui
    /// désignerait deux grades n'existe pas ici : `init?(discogsValue:)` ne devine jamais.
    private var acceptedSpellings: Set<String> {
        switch self {
        case .mint: ["mint (m)", "mint", "m"]
        case .nearMint: ["near mint (nm or m-)", "near mint", "nm or m-", "nm", "m-"]
        case .veryGoodPlus: ["very good plus (vg+)", "very good plus", "vg+"]
        case .veryGood: ["very good (vg)", "very good", "vg"]
        case .goodPlus: ["good plus (g+)", "good plus", "g+"]
        case .good: ["good (g)", "good", "g"]
        case .fair: ["fair (f)", "fair", "f"]
        case .poor: ["poor (p)", "poor", "p"]
        }
    }

    /// Grade correspondant à une valeur de champ Discogs, `nil` si elle est vide ou ne correspond à
    /// aucun grade (jamais de rapprochement approximatif : « Bon » ou « Excellent » restent inconnus).
    init?(discogsValue: String) {
        let normalized = discogsValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty,
              let match = Self.allCases.first(where: { $0.acceptedSpellings.contains(normalized) })
        else { return nil }
        self = match
    }
}
