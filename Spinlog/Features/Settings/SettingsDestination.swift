import SwiftUI

/// Réglage à mettre en évidence quand on arrive dans Réglages depuis un autre écran : les deux champs
/// personnalisés Discogs choisis pour le calcul de la plus-value (voir « Mon exemplaire »).
enum SettingsFieldHighlight: Hashable {
    case purchasePrice
    case mediaCondition

    /// Teinte du champ, reprise par son nom, sa pastille « Utilisé pour la plus-value » et sa ligne
    /// dans Réglages, pour qu'on les relie d'un coup d'œil. Deux oranges soutenus, l'un plus vif
    /// (prix d'achat), l'autre plus brûlé (état), distinguent les champs sans rompre l'harmonie.
    var tint: Color {
        switch self {
        case .purchasePrice: Color.gainFieldPurchase
        case .mediaCondition: Color.gainFieldCondition
        }
    }
}

/// Écrans poussés depuis Réglages. Des liens à valeur (et non à vue) : la pile de l'onglet est
/// alors portée par `TabNavigationCoordinator.settingsPath`, ce qui permet au re-tap sur l'onglet
/// de revenir à la racine — les liens à vue ne peuvent pas être dépilés par programme.
enum SettingsDestination: Hashable {
    case userProfile(username: String)
    case tags
    case folders
    case artistSort
    case purchasePriceHelp
    case offline
    case colorTheme
    case guide
    case guideSection(GuideSection)
    #if DEBUG
    case developerOptions
    #endif

    @ViewBuilder
    var view: some View {
        switch self {
        case .userProfile(let username):
            UserProfileSheet(username: username)
        case .tags:
            TagManagementView()
        case .folders:
            FolderManagementView()
        case .artistSort:
            ArtistSortCustomizationView()
        case .purchasePriceHelp:
            PurchasePriceHelpSheet()
        case .offline:
            OfflineSettingsDetailView()
        case .colorTheme:
            ColorThemeSelectionView()
        case .guide:
            GuideView()
        case .guideSection(let section):
            GuideSectionView(section: section)
        #if DEBUG
        case .developerOptions:
            DeveloperOptionsView()
        #endif
        }
    }
}
