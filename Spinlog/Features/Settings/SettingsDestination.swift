import SwiftUI

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
