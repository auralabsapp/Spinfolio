import Foundation

/// Identifiants et valeurs Discogs réutilisés à plusieurs endroits, pour éviter les nombres
/// magiques dispersés dans le code (dossiers, pagination...).
enum DiscogsConstants {
    /// Dossier virtuel Discogs "All" agrégeant toute la collection, tous dossiers confondus.
    static let allFolderId = 0
    /// Dossier créé par défaut par Discogs sur tout nouveau compte.
    static let uncategorizedFolderId = 1
    /// Taille de page maximale acceptée par l'API Discogs pour les listes paginées.
    static let maxPageSize = 100
}

/// Libellés utilisateur réutilisés à l'identique par plusieurs écrans/view models (actions
/// collection/wantlist, mode hors ligne...), centralisés ici pour éviter les chaînes dupliquées
/// et garder un vocabulaire cohérent.
enum AppMessages {
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
