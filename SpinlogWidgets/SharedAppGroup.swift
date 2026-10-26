import Foundation

/// App Group et clés `UserDefaults` partagés entre l'app et l'extension de widgets. Ce fichier
/// est membre des deux cibles : recopiées à la main dans chacune (comme avant), une divergence
/// aurait vidé le widget sans aucune erreur. `nonisolated` explicite : l'extension n'isole pas
/// son code au MainActor par défaut, contrairement à l'app.
nonisolated enum SharedAppGroup {
    static let id = "group.com.auralabs.Spinlog"
    /// Instantané léger de la collection lu par le widget « Album du jour ».
    static let collectionSnapshotKey = "com.spinlog.widgetCollectionSnapshot"
    /// Accès Premium, relu par le widget.
    static let isPremiumKey = "com.spinlog.isPremium"
    /// Couleur du thème pour fond sombre et pour fond clair (Live Activity, widget).
    static let themeAccentOnDarkKey = "com.spinlog.themeAccentOnDarkRGB"
    static let themeAccentOnLightKey = "com.spinlog.themeAccentOnLightRGB"
}

/// Un disque de la collection, réduit aux seules données nécessaires à l'affichage du widget
/// (pas de dépendance au cache SwiftData complet, invisible depuis l'extension de widgets).
nonisolated struct RandomAlbumSnapshotItem: Codable, Sendable {
    let releaseId: Int
    let title: String
    let artistNames: String
    let coverURL: String?
}
