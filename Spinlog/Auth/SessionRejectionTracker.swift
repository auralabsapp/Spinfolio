import Foundation

/// Suit le refus de la session Discogs (réponse 401 : jeton révoqué sur discogs.com ou expiré) pour que
/// l'app le dise une seule fois, au lieu de laisser chaque écran afficher à sa façon une erreur
/// qui ne parle pas de la session. Règle pure, testée à part ; `DiscogsAuthManager` la porte.
nonisolated struct SessionRejectionTracker: Equatable {
    /// Le jeton du compte connecté a été refusé et aucune requête n'a réussi depuis.
    private(set) var isRejected = false

    /// Un refus 401 reçu pour une requête signée avec `usedToken`. Vrai seulement pour le premier refus
    /// de la session en cours, c'est-à-dire quand l'alerte doit être montrée. Ignoré si le jeton n'est plus
    /// celui du compte connecté (réponse tardive d'un compte quitté, connexion en cours) ou en démo.
    mutating func noteRejected(usedToken: String, currentToken: String?, isDemo: Bool) -> Bool {
        guard !isDemo, currentToken == usedToken, !isRejected else { return false }
        isRejected = true
        return true
    }

    /// Une requête signée avec `usedToken` a réussi : le refus était passager (ou la session a été rétablie).
    mutating func noteAccepted(usedToken: String, currentToken: String?) {
        guard isRejected, currentToken == usedToken else { return }
        isRejected = false
    }

    /// Cette réponse signifie-t-elle que Discogs refuse le jeton du compte ? Un 401 toujours ; un 403 seulement sur
    /// l'espace du compte connecté (ses collection, wantlist, champs, identité) : c'est ce que Discogs renvoie
    /// à une écriture avec un jeton révoqué, alors qu'un 403 ailleurs (profil privé d'un autre utilisateur…) n'a
    /// rien à voir avec la session.
    static func isRejection(status: Int, path: String, username: String?) -> Bool {
        if status == 401 { return true }
        guard status == 403, let username, !username.isEmpty else { return false }
        let path = path.lowercased()
        return path == "oauth/identity" || path.hasPrefix("users/\(username.lowercased())/")
    }

    /// Une réponse réussie prouve-t-elle que le jeton est valide ? Une écriture ou l'identité, oui ; une lecture
    /// non : Discogs sert aussi les collections publiques à un jeton révoqué, une lecture réussie ne dit rien.
    static func provesSession(method: String, path: String) -> Bool {
        method.uppercased() != "GET" || path.lowercased() == "oauth/identity"
    }

    /// Connexion ou déconnexion : on repart d'une session saine.
    mutating func reset() {
        isRejected = false
    }
}
