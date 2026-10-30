import SwiftUI

/// Grandes parties du guide (Réglages > Guide). Une page par section, avec toutes ses fiches.
/// On n'ajoute un cas que lorsque ses fiches sont rédigées : une section vide n'a pas de page.
enum GuideSection: Hashable, CaseIterable, Identifiable {
    case gettingStarted
    case library
    case record
    case stats
    case listening
    case shelving
    case alerts
    case settings

    var id: Self { self }

    // `LocalizedStringResource` : les libellés sont extraits dans le catalogue et traduits
    // (en `String`, ils s'affichaient toujours en français).
    var title: LocalizedStringResource {
        switch self {
        case .gettingStarted: "Premiers pas"
        case .library: "Collection et Wantlist"
        case .record: "Fiche d'un album"
        case .stats: "Statistiques"
        case .listening: "Écoute sur platine"
        case .shelving: "Rangement"
        case .alerts: "Alertes de prix"
        case .settings: "Réglages"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .gettingStarted: "Te connecter, ajouter tes premiers albums et comprendre collection et wantlist."
        case .library: "Affichages, tris, filtres et actions. La Wantlist fonctionne de la même façon."
        case .record: "Ce que tu trouves sur la fiche d'un album, et ce que tu peux y noter."
        case .stats: "Tes chiffres, tes répartitions, ta plus-value et ton palmarès d'écoute."
        case .listening: "Suis ce que tu écoutes, et retrouve un album du jour sur ton écran d'accueil."
        case .shelving: "Retrouve la place de chaque album dans ton meuble, selon ta façon de les classer."
        case .alerts: "Sois prévenu quand un album de ta wantlist passe sous ton prix."
        case .settings: "Hors ligne, iCloud, thèmes, exports, tags, dossiers et compte."
        }
    }

    var symbol: String {
        switch self {
        case .gettingStarted: "flag.fill"
        case .library: "square.stack.fill"
        case .record: "opticaldisc.fill"
        case .stats: "chart.bar.fill"
        case .listening: "waveform"
        case .shelving: "books.vertical.fill"
        case .alerts: "bell.fill"
        case .settings: "gearshape.fill"
        }
    }

    var color: Color {
        switch self {
        case .gettingStarted: .blue
        case .library: .orange
        case .record: .indigo
        case .stats: .green
        case .listening: .pink
        case .shelving: .teal
        case .alerts: .orange
        case .settings: .gray
        }
    }

    var entries: [GuideEntry] {
        GuideCatalog.entries(in: self)
    }
}

/// Ce qu'il faut pour utiliser une fonction. Affiché en toutes lettres sur la fiche (jamais par
/// la seule couleur), sans jamais pousser vers le paywall : le guide explique, il ne vend pas.
enum GuideAccess {
    case free
    case premium
    /// Gratuit, mais l'action porte sur le compte Discogs (ajout à la collection, par exemple).
    case requiresAccount
}

/// Où mène le bouton « Essayer » d'une fiche. Un simple onglet pour l'instant : le guide reste
/// une page de consultation, c'est l'utilisateur qui navigue ensuite.
enum GuideDestination: Hashable {
    case tab(AppTab)

    /// Le coordinateur est injectable pour tester la règle sans passer par le singleton.
    func open(using coordinator: TabNavigationCoordinator = .shared) {
        switch self {
        case .tab(let tab):
            // Le guide est empilé dans l'onglet Réglages : sans retour à la racine, la liste
            // des comptes et de la démo, que les fiches de départ désignent, resterait masquée.
            if tab == .settings {
                coordinator.settingsPath = NavigationPath()
            }
            coordinator.selectedTab = tab
        }
    }
}

/// Maquette affichée en tête d'une fiche (voir `GuideVisualView`) : un morceau d'interface
/// redessiné avec les jetons de l'app, plutôt qu'une capture. Traduit, clair/sombre et couleurs
/// du thème suivent tout seuls, et rien ne vieillit dans le bundle.
enum GuideVisual {
    /// Les trois boutons de l'écran de connexion.
    case signIn
    /// La barre de recherche, icône de scan mise en évidence.
    case searchBar
    /// Les boutons « Collection » et « Wantlist », avant puis après l'ajout.
    case collectionAndWantlist
    /// Plusieurs codes-barres scannés d'un coup vers la collection.
    case batchScan
    /// Liste, mosaïque et carrousel côte à côte.
    case displayModes
    /// Sections par lettre et barre de navigation rapide.
    case sortAndIndex
    /// Recherche et puces de filtres actifs.
    case filters
    /// Les quatre actions d'une ligne (écoute, rangement, modification, suppression).
    case rowActions
    /// Liste de titres d'une fiche.
    case tracklist
    /// Plusieurs exemplaires d'un même disque.
    case copies
    /// Tags et note sur 5.
    case tagsAndRating
    /// Prix d'achat face à la cote Discogs.
    case price
    /// Les trois compteurs de l'onglet Stats.
    case statsCounters
    /// Un graphique en anneau et un histogramme.
    case statsCharts
    /// Total investi, cote actuelle et plus-value latente.
    case gain
    /// Podium des disques les plus écoutés.
    case podium
    /// Boutons d'écoute et pastille « Écoute en cours » d'une fiche.
    case listening
    /// Bandeau de Live Activity.
    case liveActivity
    /// Réglage de connexion Apple Music.
    case appleMusic
    /// Widget « Album du jour ».
    case widget
    /// Disque cible entre ses deux voisins, avec sa position.
    case shelfPlacement
    /// Les quatre règles de classement.
    case shelfMethod
    /// Noms d'artistes classés avec articles et noms de famille.
    case artistNames
    /// Catégories de supports et périmètre de dossier.
    case shelfScope
    /// Ligne de wantlist avec sa pastille d'alerte.
    case alertRow
    /// Cotes par état et raccourcis de pourcentage.
    case alertSuggestions
    /// Alerte déclenchée (cloche verte).
    case alertTriggered
    /// Archive hors ligne et progression.
    case offline
    /// Interrupteur de synchronisation iCloud.
    case iCloud
    /// Pastilles de palettes de couleurs.
    case themes
    /// Lignes d'export CSV et PDF.
    case exports
    /// Tags avec compteurs et dossier par défaut.
    case tagsAndFolders
    /// Profil Discogs et déconnexion.
    case account
}

/// Une fiche du guide : un visuel, un titre, une phrase. Les étapes et l'astuce sont repliées
/// derrière « Détails » pour que la page se lise d'un coup d'œil. Les fiches sont des données
/// (voir `GuideCatalog`) : ajouter une fonction au guide ne demande aucune nouvelle vue.
struct GuideEntry: Identifiable {
    let id: String
    let section: GuideSection
    let visual: GuideVisual
    let title: LocalizedStringResource
    let summary: LocalizedStringResource
    let steps: [LocalizedStringResource]
    var tip: LocalizedStringResource? = nil
    var access: GuideAccess = .free
    var destination: GuideDestination? = nil
    /// Page d'explication complète poussée dans la pile de Réglages (où vit le guide), pour les
    /// fonctions dont une fiche ne peut pas tout dire (ex. suivi de plus-value). Jamais réservée au
    /// Premium : comprendre une fonction ne demande pas d'abonnement.
    var explanationPage: SettingsDestination? = nil

    var hasDetails: Bool {
        !steps.isEmpty || tip != nil
    }

    /// Étapes avec leur numéro, pour une identité stable dans `ForEach`.
    var numberedSteps: [NumberedStep] {
        steps.enumerated().map { NumberedStep(number: $0.offset + 1, text: $0.element) }
    }

    struct NumberedStep: Identifiable {
        let number: Int
        let text: LocalizedStringResource
        var id: Int { number }
    }
}
