import Foundation

/// Nom marketing de l'app tel qu'affiché à l'utilisateur (paywall, mentions Discogs, etc.).
/// Centralisé ici — plutôt qu'écrit en dur à chaque endroit de l'interface où il apparaît —
/// pour ne modifier qu'un seul endroit en cas de renommage futur de l'app. Ne touche pas aux
/// identifiants techniques déjà figés ailleurs (Bundle ID, App Group, clés UserDefaults,
/// identifiants StoreKit...), qui doivent rester stables indépendamment du nom affiché.
nonisolated enum AppInfo {
    static let name = "Spinfolio"
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
    static let websiteURL = URL(string: "https://www.discogs.com")!

    /// TTL de 6h partagé par tous les caches locaux (collection, wantlist, images...),
    /// conformément à la contrainte de fraîcheur des données de l'API Discogs.
    static let sixHoursTTL: TimeInterval = 6 * 3600

    /// TTL de 24h partagé par les caches d'estimation de cote/taux de change (une seule
    /// actualisation par jour suffit, ces valeurs ne fluctuent pas assez vite pour justifier plus).
    static let oneDayTTL: TimeInterval = 24 * 3600
}

/// Délais d'interface partagés (toasts, attente de fin de scroll avant repositionnement...),
/// centralisés pour garder des durées cohérentes entre écrans plutôt que des littéraux dupliqués.
nonisolated enum AppTiming {
    /// Durée d'affichage du toast "Lecture stoppée" avant disparition automatique.
    static let toastDismissShort: Duration = .seconds(3)
    /// Durée d'affichage du toast "Lecture démarrée" avant disparition automatique.
    static let toastDismissLong: Duration = .seconds(4)
    /// Courte pause laissant le temps à un scroll animé de s'installer avant une action suivante
    /// (ex. re-scroller vers le haut après un changement de tri/filtre).
    static let scrollSettleDelay: Duration = .milliseconds(50)
}

/// Identifiants ("kind") des widgets WidgetKit, partagés entre le déclencheur de rafraîchissement
/// côté app (`WidgetCenter.reloadTimelines(ofKind:)`) et la déclaration du widget côté extension
/// (dupliqué là-bas : les deux cibles ne partagent pas de fichiers Swift entre elles).
nonisolated enum WidgetKinds {
    static let randomAlbum = "RandomAlbumWidget"
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
nonisolated enum AppMessages {
    static let loginRequiredForCollection = "Connecte-toi à Discogs pour ajouter à ta collection."
    static let loginRequiredForWantlist = "Connecte-toi à Discogs pour ajouter à ta wantlist."

    static let offlineStaleAddBlocked = "Mode hors ligne (données de plus de 6h) : ajout bloqué."
    static let offlineStaleModificationBlocked = "Mode hors ligne (données de plus de 6h) : modification bloquée."
    static let offlineStaleRemovalBlocked = "Mode hors ligne (données de plus de 6h) : retrait bloqué."

    static let addedToCollection = "Ajouté à la collection."
    static let addedToWantlist = "Ajouté à la wantlist."
    static let removedFromWantlist = "Retiré de la wantlist."

    static let offlineAddQueued = "Ajout enregistré hors ligne (sera synchronisé à la reconnexion)."
    static let offlineRemovalQueued = "Retrait enregistré hors ligne (sera synchronisé à la reconnexion)."
}
