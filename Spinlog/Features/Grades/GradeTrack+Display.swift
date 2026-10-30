import SwiftUI

/// Présentation des parcours de grades : titres, symbole, couleur d'étiquette et noms des grades.
extension GradeTrack {
    var title: LocalizedStringKey {
        switch self {
        case .collection: "Collection"
        case .listening: "Écoute sur platine"
        }
    }

    /// Même titre en `String`, pour les libellés d'accessibilité et les résumés.
    var titleText: String {
        switch self {
        case .collection: String(localized: "Collection")
        case .listening: String(localized: "Écoute sur platine")
        }
    }

    /// Ce que compte la jauge (toujours au pluriel : le nombre cible vaut au moins 10, sauf le tout
    /// premier palier, où le libellé reste correct sans accord).
    var unitCaption: LocalizedStringResource {
        switch self {
        case .collection: "albums distincts"
        case .listening: "écoutes sur platine"
        }
    }

    var symbol: String {
        switch self {
        case .collection: "square.stack.fill"
        case .listening: "opticaldisc.fill"
        }
    }

    var labelColor: Color {
        switch self {
        case .collection: Color.spinlogPink
        case .listening: Color.gradeListeningLabel
        }
    }

    /// Nom du grade d'indice `tier` (0 = premier grade).
    func tierName(_ tier: Int) -> LocalizedStringResource {
        switch (self, tier) {
        case (.collection, 0): "Premier sillon"
        case (.collection, 1): "Amateur"
        case (.collection, 2): "Collectionneur"
        case (.collection, 3): "Passionné"
        case (.collection, 4): "Disquaire"
        case (.collection, 5): "Archiviste"
        case (.collection, _): "Légende"
        case (.listening, 0): "Première rotation"
        case (.listening, 1): "Auditeur"
        case (.listening, 2): "Habitué"
        case (.listening, 3): "Mélomane"
        case (.listening, 4): "Platiniste"
        case (.listening, 5): "Disc-jockey de salon"
        case (.listening, _): "Maître du sillon"
        }
    }

    /// Condition pour atteindre le grade d'indice `tier` (ex. « À 250 disques »).
    func condition(forTier tier: Int) -> String {
        let threshold = thresholds[min(max(tier, 0), thresholds.count - 1)]
        switch self {
        case .collection: return String(localized: "À \(threshold) albums")
        case .listening: return String(localized: "À \(threshold) écoutes")
        }
    }
}
