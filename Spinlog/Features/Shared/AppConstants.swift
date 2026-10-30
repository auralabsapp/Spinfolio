import Foundation

/// Nom marketing de l'app tel qu'affiché à l'utilisateur (paywall, mentions Discogs, etc.).
/// Centralisé ici — plutôt qu'écrit en dur à chaque endroit de l'interface où il apparaît —
/// pour ne modifier qu'un seul endroit en cas de renommage futur de l'app. Ne touche pas aux
/// identifiants techniques déjà figés ailleurs (Bundle ID, App Group, clés UserDefaults,
/// identifiants StoreKit...), qui doivent rester stables indépendamment du nom affiché.
nonisolated enum AppInfo {
    static var name: String { String(localized: "Spinfolio") }
    /// Sous-système commun à tous les `Logger` de l'app, pour filtrer ses journaux d'un coup
    /// dans Console (trois valeurs différentes coexistaient). L'extension de widgets écrit la
    /// même valeur en dur, faute d'accès à cette constante.
    static let logSubsystem = "com.auralabs.Spinlog"
    /// CLUF standard d'Apple : couvre les conditions d'utilisation de l'app en l'absence de
    /// conditions personnalisées renseignées dans App Store Connect.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://auralabsapp.github.io/Spinfolio/privacy.html")!
}

/// Clés `UserDefaults` du mode d'affichage (Liste, Mosaïque, Carrousel) de chaque onglet.
nonisolated enum DisplayPreferenceKeys {
    static let collection = "collectionDisplayMode"
    static let wantlist = "wantlistDisplayMode"
}

/// Identifiants et valeurs Discogs réutilisés à plusieurs endroits, pour éviter les nombres
/// magiques dispersés dans le code (dossiers, pagination...).
nonisolated enum DiscogsConstants {
    /// Dossier virtuel Discogs "All" agrégeant toute la collection, tous dossiers confondus.
    static let allFolderId = 0
    /// Dossier créé par défaut par Discogs sur tout nouveau compte.
    static let uncategorizedFolderId = 1
    /// Taille de page maximale acceptée par l'API Discogs pour les listes paginées.
    static let maxPageSize = 100
    /// Hôte de l'API Discogs (distinct de `websiteURL` ci-dessous) — avant cette constante,
    /// cette même chaîne était retapée à la main dans `DiscogsAPIClient` et `DiscogsAuthManager`
    /// (handshake OAuth), sans qu'une faute de frappe dans l'une des deux copies soit détectée.
    static let apiBaseURL = URL(string: "https://api.discogs.com")!
    static let websiteURL = URL(string: "https://www.discogs.com")!
    /// URL officielle de suppression définitive de compte Discogs (Guideline Apple 5.1.1(v))
    static let accountDeletionURL = websiteURL.appendingPathComponent("users/delete")
    /// Page d'inscription Discogs. Pas de lien direct vers `login.discogs.com/u/signup?state=…` :
    /// ce `state` est un jeton de session à usage unique qui expire ; cette page en génère un neuf
    /// à chaque ouverture avant de rediriger vers le formulaire d'inscription.
    static let accountCreationURL = websiteURL.appendingPathComponent("users/create")

    /// TTL de 6h partagé par tous les caches locaux (collection, wantlist, images...),
    /// conformément à la contrainte de fraîcheur des données de l'API Discogs.
    static let sixHoursTTL: TimeInterval = 6 * 3600

    /// Durée maximale de conservation des pochettes sur le disque, comptée depuis leur
    /// téléchargement : sans prolongation à la consultation (voir `KingfisherConfig`), sinon une
    /// pochette souvent consultée ne serait jamais effacée. Le mode hors ligne les retélécharge à
    /// chaque synchronisation (automatique en Wi-Fi si l'utilisateur l'a activée).
    static let imageDiskRetentionDays = 7

    /// TTL de 24h partagé par les caches d'estimation de cote/taux de change (une seule
    /// actualisation par jour suffit, ces valeurs ne fluctuent pas assez vite pour justifier plus).
    static let oneDayTTL: TimeInterval = 24 * 3600
}

/// Délais d'interface partagés (toasts, attente de fin de scroll avant repositionnement...),
/// centralisés pour garder des durées cohérentes entre écrans plutôt que des littéraux dupliqués.
nonisolated enum AppTiming {
    /// Durée d'affichage du toast "Lecture stoppée" avant disparition automatique.
    static let toastDismissShort: Duration = .seconds(3)
    /// Courte pause laissant le temps à un scroll animé de s'installer avant une action suivante
    /// (ex. re-scroller vers le haut après un changement de tri/filtre).
    static let scrollSettleDelay: Duration = .milliseconds(50)
}

/// Identifiants ("kind") des widgets WidgetKit, partagés entre le déclencheur de rafraîchissement
/// côté app (`WidgetCenter.reloadTimelines(ofKind:)`) et la déclaration du widget côté extension
/// (dupliqué là-bas : les deux cibles ne partagent pas de fichiers Swift entre elles).
nonisolated enum WidgetKinds {
    static var randomAlbum: String { String(localized: "RandomAlbumWidget") }
}

/// Identifiant du App Group partagé par l'app, le widget et la Live Activity — nécessaire pour
/// toute donnée qui doit traverser ces cibles. Avant cette constante, cette chaîne était retapée
/// à la main dans `PremiumStore`, `AppTheme` et `WidgetSnapshotStore`.
nonisolated enum AppGroup {
    static let id = SharedAppGroup.id
}

/// Clé UserDefaults (App Group) du statut premium. Avant cette constante, `PremiumStore.storageKey`
/// (la source de vérité) était `private`, forçant `AppTheme` et `WidgetSnapshotStore` à retaper la
/// même chaîne à la main pour lire le même statut — une faute de frappe dans une seule des copies
/// aurait désynchronisé silencieusement leur lecture du statut réel de `PremiumStore`.
nonisolated enum PremiumConstants {
    static let isPremiumDefaultsKey = SharedAppGroup.isPremiumKey
}

/// Contraintes de saisie pour les tags (donnée 100% locale à l'app, non liée à Discogs).
nonisolated enum TagConstants {
    /// Longueur maximale d'un nom de tag, à la création comme au renommage.
    static let maxNameLength = 20
    /// Nombre maximal de tags attribuables à un même exemplaire, pour que l'affichage
    /// (pastilles individuelles dans la vue release) reste lisible sans troncature ni débordement.
    static let maxTagsPerInstance = 6
}

/// Libellés utilisateur réutilisés à l'identique par plusieurs écrans/view models (actions
/// collection/wantlist, mode hors ligne...), centralisés ici pour éviter les chaînes dupliquées
/// et garder un vocabulaire cohérent.
///
/// Propriétés calculées `String(localized:)` (et non `static let` de simples `String`) : les
/// textes sont ainsi extraits dans le catalogue et traduits selon la langue de l'appareil, au
/// lieu de s'afficher en français quelle que soit la langue.
nonisolated enum AppMessages {
    static var loginRequiredForCollection: String { String(localized: "Connecte-toi à Discogs pour ajouter à ta collection.") }
    static var loginRequiredForWantlist: String { String(localized: "Connecte-toi à Discogs pour ajouter à ta wantlist.") }

    static var offlineStaleAddBlocked: String { String(localized: "Mode hors ligne (données de plus de 6h) : ajout bloqué.") }
    static var offlineStaleModificationBlocked: String { String(localized: "Mode hors ligne (données de plus de 6h) : modification bloquée.") }
    static var offlineStaleRemovalBlocked: String { String(localized: "Mode hors ligne (données de plus de 6h) : retrait bloqué.") }

    static var addedToCollection: String { String(localized: "Ajouté à la collection.") }


    static var discogsUnavailableQueued: String { String(localized: "Discogs ne répond pas : la modification sera synchronisée automatiquement.") }
    static var addFailed: String { String(localized: "Impossible d'ajouter cet album sur Discogs.") }
    static var removalFailed: String { String(localized: "Impossible de supprimer cet album sur Discogs.") }
    static var moveFailed: String { String(localized: "Impossible de changer cet album de dossier sur Discogs.") }

    // Mode démo (voir `DemoMode`) : la collection et la wantlist d'exemple sont en lecture seule.
    static var demoAddBlocked: String { String(localized: "En mode démo, il n'est pas possible d'ajouter des albums à la collection ou à la wantlist. Connecte ton compte Discogs dans Réglages pour gérer ta propre collection.") }
    static var demoRemovalBlocked: String { String(localized: "En mode démo, il n'est pas possible de supprimer des albums de la collection ou de la wantlist. Connecte ton compte Discogs dans Réglages pour gérer ta propre collection.") }
    static var demoModificationBlocked: String { String(localized: "En mode démo, la collection et la wantlist ne peuvent pas être modifiées. Connecte ton compte Discogs dans Réglages pour gérer ta propre collection.") }

    // Premium (voir `SubscriptionManager`) : achat à vie et codes d'offre.
    static var lifetimeKeepsSubscription: String { String(localized: "Tu as Premium pour toujours. Ton abonnement n'est pas résilié automatiquement : résilie-le pour ne plus être facturé.") }
    static var offerCodeRedeemed: String { String(localized: "Code utilisé : ton Premium est activé.") }
    static var offerCodeFailed: String { String(localized: "Le code n'a pas pu être utilisé. Vérifie-le et réessaie.") }
    static var restoreNothingFound: String { String(localized: "Aucun achat à restaurer pour ce compte Apple.") }
    static var restoreFailed: String { String(localized: "La restauration a échoué. Vérifie ta connexion et réessaie.") }
    static var purchaseVerificationFailed: String { String(localized: "L'achat n'a pas pu être vérifié auprès de l'App Store.") }
}
