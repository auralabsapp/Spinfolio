import Foundation

/// Point d'accès partagé par toute l'app aux champs personnalisés Discogs (dossiers, prix
/// d'achat, état du média...), pour éviter que chaque écran (collection, réglages, édition d'un
/// exemplaire...) ne refasse le même appel réseau indépendamment. Le cache n'expire pas en
/// mémoire pour la durée de vie du process : ces champs ne changent que si l'utilisateur en
/// crée ou modifie sur discogs.com, ce qui est rare.
enum CollectionFieldsService {
    /// Champs déjà récupérés, par compte : une liste unique servait sinon au compte suivant (ou
    /// à la démo) les champs du compte précédent. Vidée à la déconnexion.
    private static var cache = CollectionFieldsCache()

    static func fields(username: String, credentials: DiscogsCredentials?) async -> [CollectionField] {
        if let cached = cache.fields(for: username) {
            return cached
        }
        guard let credentials,
              let response = try? await DiscogsAPIClient.shared.collectionFields(username: username, credentials: credentials) else {
            return []
        }
        cache.store(response.fields, for: username)
        return response.fields
    }

    /// Oublie les champs mis en cache (déconnexion, sortie de démo).
    static func clearCache() {
        cache.removeAll()
    }
}
