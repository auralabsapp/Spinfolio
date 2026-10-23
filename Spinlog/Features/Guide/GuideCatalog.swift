import SwiftUI

/// Contenu du guide. Une fiche = un visuel, un titre, une phrase ; les étapes et l'astuce
/// (repliées sous « Détails ») restent courtes : 2 étapes au plus, une astuce seulement quand il
/// y a un vrai piège. Les libellés de boutons cités reprennent ceux de l'interface : en cas de
/// renommage d'un bouton, la fiche correspondante est à mettre à jour.
enum GuideCatalog {
    static let entries: [GuideEntry] = gettingStarted + library + record + stats + listening + shelving + alerts + settings

    static func entries(in section: GuideSection) -> [GuideEntry] {
        entries.filter { $0.section == section }
    }

    // MARK: - Premiers pas

    private static let gettingStarted: [GuideEntry] = [
        GuideEntry(
            id: "connect",
            section: .gettingStarted,
            visual: .signIn,
            title: "Se connecter à Discogs",
            summary: "Ta collection vit sur Discogs : Spinlog en est une belle vitrine.",
            steps: [
                "Autorise l'app sur le site Discogs, puis reviens dans Spinlog.",
                "Ta collection et ta wantlist se chargent."
            ],
            tip: "Les ajouts, les retraits et les notes sont répercutés sur ton compte Discogs. Les tags, eux, restent propres à Spinlog.",
            destination: .tab(.settings)
        ),
        GuideEntry(
            id: "addRecord",
            section: .gettingStarted,
            visual: .searchBar,
            title: "Ajouter un disque",
            summary: "Cherche par nom ou scanne le code-barres.",
            steps: [
                "Onglet Recherche : tape un nom ou touche l'icône de scan.",
                "Sur la fiche, touche « Collection » ou « Wantlist »."
            ],
            tip: "Maintiens « Collection » pour choisir un autre dossier.",
            access: .requiresAccount,
            destination: .tab(.search)
        ),
        GuideEntry(
            id: "collectionOrWantlist",
            section: .gettingStarted,
            visual: .collectionAndWantlist,
            title: "Collection ou wantlist ?",
            summary: "La collection, ce sont les disques que tu possèdes ; la wantlist, ceux que tu cherches.",
            steps: [
                "Le bouton affiche ensuite « En collection » ou « En wantlist ».",
                "Retrouve tes disques dans les onglets Collection et Wantlist."
            ],
            tip: "Tu peux posséder un disque en plusieurs exemplaires : maintiens « En collection » pour en ajouter un autre."
        ),
        GuideEntry(
            id: "batchScan",
            section: .gettingStarted,
            visual: .batchScan,
            title: "Scan par lot",
            summary: "Scanne plusieurs disques à la suite, chez un disquaire ou en brocante.",
            steps: [
                "Dans l'onglet Recherche, touche l'icône de scan par lot, à côté de celle du scan.",
                "Ajoute-les d'un coup à ta collection ou à ta wantlist."
            ],
            tip: "Un lot en cours est conservé : une confirmation te protège si tu fermes l'écran par erreur.",
            access: .premium,
            destination: .tab(.search)
        )
    ]

    // MARK: - Collection et Wantlist

    private static let library: [GuideEntry] = [
        GuideEntry(
            id: "displayModes",
            section: .library,
            visual: .displayModes,
            title: "Trois affichages",
            summary: "Liste, mosaïque ou carrousel : choisis ce qui te parle.",
            steps: [
                "Touche « ··· » en haut à droite, puis « Affichage ».",
                "Ton choix est retenu, séparément pour la Collection et la Wantlist."
            ],
            tip: "Le bouton « Disque au hasard », en haut de la Collection, t'en propose un.",
            destination: .tab(.collection)
        ),
        GuideEntry(
            id: "sort",
            section: .library,
            visual: .sortAndIndex,
            title: "Trier et naviguer",
            summary: "Jusqu'à dix tris, dans les deux sens, et une barre pour sauter à une lettre.",
            steps: [
                "Touche « ··· », puis « Tri » : choisis un critère et le sens.",
                "Glisse le doigt sur la barre à droite pour sauter à une lettre ou à une année."
            ],
            tip: "Le tri « Meuble » suit ta règle de rangement (Réglages > Rangement).",
            destination: .tab(.collection)
        ),
        GuideEntry(
            id: "filter",
            section: .library,
            visual: .filters,
            title: "Chercher et filtrer",
            summary: "Par texte, dossier, tag ou support. Les filtres se cumulent.",
            steps: [
                "Tape dans la barre de recherche, ou touche « ··· » puis « Filtres » pour le tag et le support.",
                "Le menu « Dossier », dans « ··· », change de dossier."
            ],
            tip: "Avec plusieurs tags, seuls les disques qui les portent tous restent affichés.",
            destination: .tab(.collection)
        ),
        GuideEntry(
            id: "rowActions",
            section: .library,
            visual: .rowActions,
            title: "Agir sur un disque",
            summary: "Glisse une ligne, ou maintiens-la, pour écouter, ranger, modifier ou supprimer.",
            steps: [
                "Touche « ··· » puis « Sélectionner » pour agir sur plusieurs disques à la fois : dossier, tags, suppression."
            ],
            tip: "« Ranger » est une fonction Premium.",
            destination: .tab(.collection)
        )
    ]

    // MARK: - Fiche d'un disque

    private static let record: [GuideEntry] = [
        GuideEntry(
            id: "readRecord",
            section: .record,
            visual: .tracklist,
            title: "Lire une fiche",
            summary: "Titres, crédits, photos, vidéos et infos de pressage, au même endroit.",
            steps: [
                "Touche un disque pour ouvrir sa fiche.",
                "Fais défiler : titres, « Photos et vidéos », « Autres informations »."
            ],
            tip: "Depuis la fiche, tu peux écouter un titre : extrait de 30 s, ou en entier avec Apple Music (Réglages > Écoute et Apple Music)."
        ),
        GuideEntry(
            id: "copies",
            section: .record,
            visual: .copies,
            title: "Plusieurs exemplaires",
            summary: "Un même disque peut exister en plusieurs exemplaires, chacun avec son dossier.",
            steps: [
                "Maintiens « En collection » pour ajouter un exemplaire.",
                "Touche « Modifier » sur un exemplaire : dossier, tags, champs Discogs."
            ],
            access: .requiresAccount
        ),
        GuideEntry(
            id: "tagsAndRating",
            section: .record,
            visual: .tagsAndRating,
            title: "Tags et note",
            summary: "Classe tes disques avec tes tags et une note sur 5.",
            steps: [
                "Dans « Modifier », section « Tags de l'exemplaire » : crée ou choisis des tags.",
                "Touche les étoiles de « Ma note de la release » pour noter."
            ],
            tip: "Les tags restent dans Spinlog (synchronisés par iCloud avec Premium), pas sur Discogs.",
            access: .requiresAccount
        ),
        GuideEntry(
            id: "price",
            section: .record,
            visual: .price,
            title: "Prix d'achat et cote",
            summary: "Note ce que tu as payé et compare avec la cote Discogs.",
            steps: [
                "Une seule fois : Réglages > Suivi de plus-value, puis associe tes champs Discogs.",
                "Ensuite, « Modifier » sur un exemplaire pour saisir son prix."
            ],
            tip: "La plus-value (cote moins prix payé) est une fonction Premium, dans Stats.",
            access: .requiresAccount,
            destination: .tab(.settings)
        )
    ]

    // MARK: - Statistiques

    private static let stats: [GuideEntry] = [
        GuideEntry(
            id: "statsOverview",
            section: .stats,
            visual: .statsCounters,
            title: "Ta collection en chiffres",
            summary: "Compteurs, derniers ajouts et estimation de la valeur de ta collection.",
            steps: [
                "Dans l'onglet Stats, touche « Collection » ou « Wantlist » pour aller à la liste.",
                "« Estimation de la collection » s'appuie sur l'historique des ventes Discogs."
            ],
            tip: "Les compteurs et la cote demandent une connexion réseau ; le reste fonctionne aussi hors ligne.",
            access: .requiresAccount,
            destination: .tab(.stats)
        ),
        GuideEntry(
            id: "statsCharts",
            section: .stats,
            visual: .statsCharts,
            title: "Graphiques et répartitions",
            summary: "Genres, supports, labels, artistes et années, en graphiques.",
            steps: [
                "Touche une portion ou une barre : la liste des disques correspondants s'ouvre.",
                "Dans « Sorties originales », bascule entre années et décennies."
            ],
            tip: "L'année de sortie originale est retrouvée disque par disque : sur une grande collection, le calcul prend un moment.",
            access: .requiresAccount,
            destination: .tab(.stats)
        ),
        GuideEntry(
            id: "gain",
            section: .stats,
            visual: .gain,
            title: "Plus-value",
            summary: "Compare ce que tu as payé à la cote actuelle de ta collection.",
            steps: [
                "Renseigne le prix d'achat de tes exemplaires.",
                "Dans Stats, ouvre « Investi vs Cote actuelle »."
            ],
            tip: "Le total investi ne compte que les exemplaires dont le prix d'achat est renseigné.",
            access: .premium,
            destination: .tab(.stats),
            explanationPage: .purchasePriceHelp
        ),
        GuideEntry(
            id: "ranking",
            section: .stats,
            visual: .podium,
            title: "Palmarès d'écoute",
            summary: "Tes albums et artistes les plus écoutés sur ta platine.",
            steps: [
                "Touche « J'écoute » sur un disque quand tu le poses sur ta platine.",
                "Dans Stats, « Tops & Palmarès » montre le classement et le podium par période."
            ],
            tip: "Les lectures Apple Music ne sont pas comptées.",
            access: .premium,
            destination: .tab(.stats)
        )
    ]

    // MARK: - Écoute sur platine

    private static let listening: [GuideEntry] = [
        GuideEntry(
            id: "listen",
            section: .listening,
            visual: .listening,
            title: "Noter une écoute",
            summary: "Touche « J'écoute » quand tu poses un disque sur ta platine.",
            steps: [
                "Sur la fiche d'un disque, ou en glissant une ligne de la Collection : « J'écoute ».",
                "Un mini-lecteur apparaît ; touche-le pour ouvrir « Écoute sur platine » et arrêter."
            ],
            tip: "Lancer une nouvelle écoute interrompt celle en cours. La fiche compte tes écoutes et garde la date de la dernière.",
            destination: .tab(.collection)
        ),
        GuideEntry(
            id: "liveActivity",
            section: .listening,
            visual: .liveActivity,
            title: "Live Activity et arrêt automatique",
            summary: "Ton disque en cours reste visible, et l'écoute s'arrête toute seule.",
            steps: [
                "Dans Réglages, ouvre « Écoute et Apple Music » et choisis la durée maximale.",
                "À la fin de cette durée, l'écoute s'arrête sans que tu aies rien à faire."
            ],
            tip: "Chaque écoute alimente le palmarès de Stats (Premium).",
            destination: .tab(.settings)
        ),
        GuideEntry(
            id: "appleMusic",
            section: .listening,
            visual: .appleMusic,
            title: "Écouter avec Apple Music",
            summary: "Lis les titres en entier depuis une fiche, avec un abonnement Apple Music.",
            steps: [
                "Dans Réglages, ouvre « Écoute et Apple Music » et active « Connecter mon compte Apple Music ».",
                "Sans connexion, un extrait de 30 s reste disponible."
            ],
            tip: "Ces lectures ne comptent pas comme des écoutes sur platine.",
            destination: .tab(.settings)
        ),
        GuideEntry(
            id: "widget",
            section: .listening,
            visual: .widget,
            title: "Widget « Album du jour »",
            summary: "Un disque de ta collection tiré au hasard chaque jour, sur ton écran d'accueil.",
            steps: [
                "Maintiens l'écran d'accueil, touche « + » et cherche Spinlog.",
                "Choisis « Album du jour », en petit, moyen ou grand format."
            ],
            tip: "Il est gratuit et se renouvelle chaque jour à minuit."
        )
    ]

    // MARK: - Rangement

    private static let shelving: [GuideEntry] = [
        GuideEntry(
            id: "shelfPlacement",
            section: .shelving,
            visual: .shelfPlacement,
            title: "Où ranger un disque",
            summary: "Le guide te donne sa position dans le meuble, entre ses deux voisins.",
            steps: [
                "Glisse une ligne de la Collection et touche « Ranger », ou ouvre « Rangement physique » sur la fiche.",
                "Repère le disque central et ses deux voisins : c'est entre eux qu'il va."
            ],
            tip: "Fonction Premium. Le guide s'ouvre aussi juste après l'ajout d'un disque à la collection.",
            access: .premium,
            destination: .tab(.collection)
        ),
        GuideEntry(
            id: "shelfMethod",
            section: .shelving,
            visual: .shelfMethod,
            title: "Ta méthode de classement",
            summary: "Quatre règles, pour classer comme dans ton meuble.",
            steps: [
                "Dans Réglages, ouvre « Rangement », puis touche « Règle de rangement dans le meuble ».",
                "Choisis : artiste puis année originale, artiste puis titre, année seule, ou artiste puis année du pressage."
            ],
            tip: "L'année originale vient du master Discogs ; le pressage peut être une réédition plus récente.",
            destination: .tab(.settings)
        ),
        GuideEntry(
            id: "artistNames",
            section: .shelving,
            visual: .artistNames,
            title: "Noms d'artistes",
            summary: "Articles, noms de famille, cas particuliers : tu règles l'ordre artiste par artiste.",
            steps: [
                "Dans Réglages > Organisation, active « Ignorer les articles (The...) » ou « Trier par nom de famille ».",
                "Avec le nom de famille, « Personnaliser le tri des artistes » corrige un cas isolé."
            ],
            tip: "Ces réglages valent pour le meuble, la Collection et la Wantlist.",
            destination: .tab(.settings)
        ),
        GuideEntry(
            id: "shelfScope",
            section: .shelving,
            visual: .shelfScope,
            title: "Supports et dossiers",
            summary: "Vinyles, CD et cassettes se rangent séparément ; les dossiers Discogs, au choix.",
            steps: [
                "Le guide compte chaque support à part : vinyles 12, 10 et 7 pouces, CD, cassettes.",
                "Active « Limiter au dossier Discogs » si tes dossiers correspondent à des meubles distincts."
            ],
            tip: "Par défaut, le guide compare avec toute ta collection, tous dossiers confondus.",
            destination: .tab(.settings)
        )
    ]

    // MARK: - Alertes de prix

    private static let alerts: [GuideEntry] = [
        GuideEntry(
            id: "alertSet",
            section: .alerts,
            visual: .alertRow,
            title: "Définir une alerte",
            summary: "Fixe le prix maximum que tu veux payer pour un disque de ta wantlist.",
            steps: [
                "Dans la Wantlist, glisse une ligne ou maintiens-la : « Définir une alerte prix ».",
                "Saisis le « Prix maximum » puis touche « Enregistrer »."
            ],
            tip: "Fonction Premium. Une pastille « ≤ prix » s'affiche ensuite sur la ligne.",
            access: .premium,
            destination: .tab(.wantlist)
        ),
        GuideEntry(
            id: "alertThreshold",
            section: .alerts,
            visual: .alertSuggestions,
            title: "Choisir le bon seuil",
            summary: "La feuille montre la cote récente par état, pour viser juste.",
            steps: [
                "Touche un état dans « Cote moyenne récente par état » : sa cote devient ton prix cible.",
                "Ajuste avec les raccourcis -10 %, -20 % ou -30 %."
            ],
            access: .premium,
            destination: .tab(.wantlist)
        ),
        GuideEntry(
            id: "alertTriggered",
            section: .alerts,
            visual: .alertTriggered,
            title: "Quand l'alerte se déclenche",
            summary: "Tu es prévenu dès qu'une annonce est à ton prix ou moins.",
            steps: [
                "La vérification se fait à l'ouverture de l'app et parfois en arrière-plan, pas en temps réel.",
                "Autorise les notifications pour être prévenu app fermée."
            ],
            tip: "Vérifie l'état exact du disque et les frais de port sur l'annonce Discogs.",
            access: .premium,
            destination: .tab(.wantlist)
        )
    ]

    // MARK: - Réglages

    private static let settings: [GuideEntry] = [
        GuideEntry(
            id: "offline",
            section: .settings,
            visual: .offline,
            title: "Mode hors ligne",
            summary: "Emporte toute ta collection et ses pochettes, même sans réseau.",
            steps: [
                "Dans Réglages > Synchronisation, ouvre « Données hors ligne » puis « Télécharger toute ma collection ».",
                "Active « Synchro auto en Wi-Fi » pour la tenir à jour."
            ],
            tip: "La synchro auto ne se lance jamais en 4G/5G, et au plus une fois toutes les 6 heures.",
            access: .premium,
            destination: .tab(.settings)
        ),
        GuideEntry(
            id: "iCloud",
            section: .settings,
            visual: .iCloud,
            title: "Synchronisation iCloud",
            summary: "Tes tags, écoutes, alertes et préférences suivent ton compte sur tous tes appareils.",
            steps: [
                "Dans Réglages > Synchronisation, ouvre « Synchronisation iCloud » et active « Synchroniser avec iCloud »."
            ],
            tip: "Couper la synchro n'efface rien : à la réactivation, tout est fusionné. Elle est coupée pendant la démo.",
            access: .premium,
            destination: .tab(.settings)
        ),
        GuideEntry(
            id: "themes",
            section: .settings,
            visual: .themes,
            title: "Apparence et couleurs",
            summary: "Thème clair ou sombre, et palettes de couleurs pour toute l'app.",
            steps: [
                "Dans Réglages > Aide & personnalisation, ouvre « Apparence » : « Mode d'affichage » pour clair, sombre ou automatique.",
                "« Couleur du thème » ouvre les palettes."
            ],
            tip: "Le thème Signature est inclus pour tous ; les 8 autres palettes sont Premium.",
            destination: .tab(.settings)
        ),
        GuideEntry(
            id: "exports",
            section: .settings,
            visual: .exports,
            title: "Exporter ta collection",
            summary: "Un tableur pour tes outils, ou un PDF à présenter à un assureur.",
            steps: [
                "Dans Réglages > Ma collection, ouvre « Export » : « Exporter la collection en CSV » ou « Déclaration de collection (PDF) »."
            ],
            tip: "Le CSV inclut métadonnées, tags et notes ; le PDF, l'état et le prix d'achat.",
            access: .premium,
            destination: .tab(.settings)
        ),
        GuideEntry(
            id: "tagsAndFolders",
            section: .settings,
            visual: .tagsAndFolders,
            title: "Tags et dossiers",
            summary: "Range ta collection à ta façon, et choisis où atterrissent les nouveaux disques.",
            steps: [
                "« Gestion des tags » : glisse ou maintiens un tag pour le renommer, le fusionner ou le supprimer.",
                "« Gestion des dossiers » : touche un dossier pour en faire le dossier d'ajout par défaut."
            ],
            tip: "« Toujours demander » te propose le dossier à chaque ajout.",
            destination: .tab(.settings)
        ),
        GuideEntry(
            id: "account",
            section: .settings,
            visual: .account,
            title: "Compte et données",
            summary: "Consulte ton profil, déconnecte-toi ou efface tes données.",
            steps: [
                "Touche ton nom en haut de Réglages pour ouvrir ton profil Discogs.",
                "« Se déconnecter » est en bas de Réglages."
            ],
            tip: "« Supprimer mon compte… » propose d'effacer les données locales et iCloud, ou de supprimer le compte sur Discogs.com.",
            access: .requiresAccount,
            destination: .tab(.settings)
        )
    ]
}
