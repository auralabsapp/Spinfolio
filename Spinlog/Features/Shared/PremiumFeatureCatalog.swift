import SwiftUI

/// Une fonction réservée au Premium (icône, titre, résumé), partagée par le paywall
/// (`SpinlogPaywallView`) et la feuille de liste (`PremiumFeaturesSheet`) : une seule liste à tenir
/// à jour, en miroir de chaque `PremiumLockedCard`/`premiumUpsellAlert` posé dans l'app.
struct PremiumFeatureInfo: Identifiable {
    let id: String
    let icon: String
    /// Couleur de l'icône dans la feuille de liste.
    let color: Color
    /// Couleur de l'icône dans le paywall, quand elle suit la charte Or Hifi plutôt que `color`.
    var paywallColor: Color?
    // `LocalizedStringResource` : les libellés sont extraits dans le catalogue et traduits
    // (en `String`, ils s'affichaient toujours en français).
    let title: LocalizedStringResource
    let description: LocalizedStringResource
}

enum PremiumFeatureCatalog {
    /// Les textes sont ceux du paywall, écran de vente de référence.
    static let all: [PremiumFeatureInfo] = [
        PremiumFeatureInfo(
            id: "gain",
            icon: "banknote.fill",
            color: .green,
            title: "Suivi de plus-value",
            description: "Compare le prix payé pour chaque album à sa cote Discogs : plus-value de chaque exemplaire et de toute ta collection dans Statistiques."
        ),
        PremiumFeatureInfo(
            id: "iCloud",
            icon: "icloud.fill",
            color: .cyan,
            title: "Synchronisation iCloud",
            description: "Synchronise tags, journal d'écoute sur platine, préférences et personnalisations de tri entre tous tes appareils connectés au même compte."
        ),
        PremiumFeatureInfo(
            id: "batchScan",
            icon: "rectangle.stack.badge.plus",
            color: .blue,
            title: "Scan par lot",
            description: "Scanne plusieurs codes-barres à la suite (brocante, disquaire) et ajoute-les en une fois à ta collection ou ta wantlist."
        ),
        PremiumFeatureInfo(
            id: "alerts",
            icon: "bell.fill",
            color: .orange,
            title: "Alertes de prix sur la wantlist",
            description: "Sois averti quand un disque de ta wantlist apparaît à bon prix sur le marketplace Discogs (vérification à l'ouverture de l'app et occasionnellement en arrière-plan, pas en temps réel)."
        ),
        PremiumFeatureInfo(
            id: "offline",
            icon: "arrow.down.circle.fill",
            color: .teal,
            title: "Mode hors ligne",
            description: "Télécharge toute ta collection et les pochettes en haute résolution pour fouiner en brocante sans aucun réseau."
        ),
        PremiumFeatureInfo(
            id: "shelving",
            icon: "books.vertical.fill",
            color: .purple,
            title: "Où ranger son album",
            description: "Retrouve instantanément où ranger un album dans ton meuble, avec ses voisins immédiats selon ton tri personnalisé."
        ),
        PremiumFeatureInfo(
            id: "listeningCharts",
            icon: "waveform",
            color: .spinlogPink,
            paywallColor: .goldWarm,
            title: "Palmarès d'écoute sur platine",
            description: "Découvre tes albums et artistes les plus écoutés sur ta platine, tes podiums du mois et de l'année dans Statistiques. Les lectures Apple Music ne sont pas comptées."
        ),
        PremiumFeatureInfo(
            id: "themes",
            icon: "paintpalette.fill",
            color: .spinlogPink,
            paywallColor: .goldAccent,
            title: "Thèmes et palettes de couleurs",
            description: "Personnalise l'ambiance visuelle de l'app selon tes goûts avec 8 palettes exclusives (Bleu Cobalt, Vert Émeraude, Orange Crépuscule, Rouge Rubis, Violet Améthyste, Cuivre & Or...)."
        ),
        PremiumFeatureInfo(
            id: "exports",
            icon: "square.and.arrow.up.fill",
            color: .mint,
            title: "Export CSV & PDF",
            description: "Exporte toute ta discothèque au format tableur (Excel, Numbers, Sheets) avec métadonnées, notes et tags, ou en PDF avec état et prix d'achat."
        )
    ]
}
