import Foundation

/// Espace de rangement physique d'un disque : les supports ne se mélangent jamais sur une même
/// étagère (un CD ne se range pas au milieu des vinyles), et parmi les vinyles, un 7" ne se range
/// pas au milieu des 12" — c'est le diamètre qui contraint le rangement, pas la vitesse de lecture
/// (33/45 tours), qui n'a aucune incidence sur la taille de la pochette à ranger.
enum ShelfMediaCategory: String, CaseIterable, Sendable {
    case vinyl12
    case vinyl10
    case vinyl7
    case cd
    case cassette
    case other

    var displayName: String {
        switch self {
        case .vinyl12: return "Vinyles 12 pouces"
        case .vinyl10: return "Vinyles 10 pouces"
        case .vinyl7: return "Vinyles 7 pouces"
        case .cd: return "CD"
        case .cassette: return "Cassettes"
        case .other: return "Autres supports"
        }
    }

    /// Variante en bas de casse pour une insertion en milieu de phrase (« sur 284 \(...) »).
    /// Ne fait PAS un simple `displayName.lowercased()` : « CD » est un sigle qui doit rester en
    /// majuscules quelle que soit sa position dans la phrase, contrairement à « Vinyles »/« Cassettes ».
    var lowercasedDisplayName: String {
        switch self {
        case .cd: return "CD"
        default: return displayName.lowercased()
        }
    }

    /// Regroupement large utilisé par le camembert "Répartition par support" des Statistiques :
    /// les 3 tailles de vinyle y comptent comme une seule part (le détail par taille n'apparaît
    /// qu'au survol/tap de cette part, voir `vinylSizeBreakdown` dans `StatsViewModel`).
    var broadFormatLabel: String {
        switch self {
        case .vinyl12, .vinyl10, .vinyl7: return "Vinyles"
        case .cd: return "CD"
        case .cassette: return "Cassettes"
        case .other: return "Autres"
        }
    }

    /// Libellé court pour les pastilles de détail par taille (contexte déjà donné par "Vinyles",
    /// pas besoin de le répéter) : « 12″ », « 10″ », « 7″ ».
    var shortSizeLabel: String {
        switch self {
        case .vinyl12: return "12″"
        case .vinyl10: return "10″"
        case .vinyl7: return "7″"
        default: return displayName
        }
    }
}

extension Release {
    /// Déduit l'espace de rangement à partir du format Discogs principal (`formats.first`).
    /// Le diamètre du vinyle est lu dans `descriptions` (ex: `"7\""`, `"10\""`, `"12\""`) ; en son
    /// absence, on suppose 12" — c'est de loin le format le plus courant pour un album, et Discogs
    /// omet souvent cette précision précisément quand il s'agit du cas par défaut.
    var shelfMediaCategory: ShelfMediaCategory {
        guard let primary = formats?.first else { return .other }
        let name = primary.name.lowercased()
        let descriptors = (primary.descriptions ?? []).map { $0.lowercased() }

        if name.contains("vinyl") {
            if descriptors.contains(where: { $0.contains("7\"") }) {
                return .vinyl7
            }
            if descriptors.contains(where: { $0.contains("10\"") }) {
                return .vinyl10
            }
            return .vinyl12
        }
        if name.contains("cd") {
            return .cd
        }
        if name.contains("cassette") {
            return .cassette
        }
        return .other
    }
}
