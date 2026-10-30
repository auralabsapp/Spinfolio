import Foundation
import AuthenticationServices
import UIKit
import Observation
import WidgetKit

/// Orchestre le flow OAuth 1.0a "3-legged" de Discogs (request token → autorisation
/// navigateur → access token) et conserve les tokens obtenus dans le Keychain.
/// Référence : https://www.discogs.com/developers#page:authentication,header:authentication-oauth-flow
@Observable
@MainActor
final class DiscogsAuthManager: NSObject {
    static let shared = DiscogsAuthManager()

    private(set) var isAuthenticated: Bool
    private(set) var username: String?
    private(set) var avatarURL: String?
    private(set) var isAuthenticating = false
    /// Session de démonstration sans compte Discogs (voir `DemoMode`).
    private(set) var isDemoMode: Bool
    var lastError: String?

    private let keychain = KeychainStore()
    private let signer = OAuth1Signer(
        consumerKey: DiscogsSecrets.consumerKey,
        consumerSecret: DiscogsSecrets.consumerSecret
    )
    private let callbackURL = URL(string: "spinlog://oauth-callback")!
    private var webAuthSession: ASWebAuthenticationSession?

    /// Mis en cache en mémoire plutôt que relu au Keychain à chaque accès (voir `init`/`login`/
    /// `logout`) : `SecItemCopyMatching` fait un aller-retour XPC synchrone vers `securityd`
    /// (~15-30ms), et cette propriété est lue à 40+ endroits dans l'app — dont `loadMoreIfNeeded`,
    /// appelée à chaque page chargée pendant le défilement de la Collection/Wantlist, ce qui
    /// bloquait le thread principal (`DiscogsAuthManager` est `@MainActor`) et provoquait les
    /// saccades observées dans Instruments.
    private(set) var credentials: DiscogsCredentials?

    /// Regroupe `username`/`credentials` en une seule valeur optionnelle, pour remplacer le
    /// `guard let username = ..., let credentials = ...` répété à l'identique dans une douzaine
    /// d'endroits de l'app par un unique `guard let session = authManager.session`.
    var session: (username: String, credentials: DiscogsCredentials)? {
        guard let username, let credentials else { return nil }
        return (username, credentials)
    }

    private typealias Keys = KeychainKeys

    private override init() {
        let keychain = KeychainStore()
        keychain.migrateAccessibilityIfNeeded()
        // La démo ne survit jamais à un relancement (voir `DemoMode.isActive`).
        self.isDemoMode = false
        let token = keychain.get(Keys.accessToken)
        self.isAuthenticated = token != nil
        self.username = keychain.get(Keys.username)
        self.avatarURL = keychain.get(Keys.avatarURL)
        if let token, let secret = keychain.get(Keys.accessTokenSecret) {
            self.credentials = DiscogsCredentials(token: token, tokenSecret: secret)
        }
        super.init()
        if DemoMode.hasLeftoverSession {
            Self.clearDemoData()
        }
        // Propage le compte déjà connu (relance de l'app) aux stores isolés par compte, pour
        // qu'ils chargent tout de suite les bonnes données plutôt que de démarrer à vide.
        TagStore.shared.setActiveUsername(self.username)
        ListeningLogStore.shared.setActiveUsername(self.username)
        GradeStore.shared.setActiveUsername(self.username)
        ShelfPreferencesStore.shared.setActiveUsername(self.username)
        // Jamais de synchro iCloud pour la démo : rien à conserver, et l'appareil d'un testeur
        // ne doit pas recevoir de zone CloudKit à ce nom.
        CloudSyncEngine.shared.setActiveUsername(isDemoMode ? nil : self.username)
        WantlistAlertStore.shared.setActiveUsername(self.username)
    }

    func login() async {
        guard !DiscogsSecrets.consumerKey.isEmpty, !DiscogsSecrets.consumerSecret.isEmpty else {
            lastError = String(localized: "Ajoute ton Consumer Key et Consumer Secret Discogs dans Secrets.swift (crée une app sur discogs.com/settings/developers) pour activer la connexion.")
            return
        }
        guard !isAuthenticating else { return }
        // Connexion d'un vrai compte depuis la démo : on quitte d'abord la démo, pour ne pas
        // mélanger ses données d'exemple avec celles du compte.
        if isDemoMode {
            logout()
        }
        isAuthenticating = true
        lastError = nil
        defer { isAuthenticating = false }

        do {
            let requestToken = try await fetchRequestToken()
            let verifier = try await authorize(requestToken: requestToken.token)
            let accessToken = try await fetchAccessToken(
                requestToken: requestToken.token,
                requestTokenSecret: requestToken.secret,
                verifier: verifier
            )

            let identity: Identity = try await DiscogsAPIClient.shared.request(
                path: "oauth/identity",
                credentials: DiscogsCredentials(token: accessToken.token, tokenSecret: accessToken.secret)
            )
            // Tokens et nom d'utilisateur écrits ensemble, uniquement une fois l'identité
            // obtenue : si `oauth/identity` échouait après l'écriture des tokens, l'app se
            // croyait connectée au relancement (`isAuthenticated` ne dépend que du token) sans
            // nom d'utilisateur, donc incapable de charger quoi que ce soit.
            keychain.set(accessToken.token, forKey: Keys.accessToken)
            keychain.set(accessToken.secret, forKey: Keys.accessTokenSecret)
            keychain.set(identity.username, forKey: Keys.username)
            username = identity.username
            credentials = DiscogsCredentials(token: accessToken.token, tokenSecret: accessToken.secret)
            // Toute connexion (première, ou après la déconnexion d'un autre compte) arrive sur Collection,
            // jamais sur l'onglet laissé ouvert par la session précédente.
            TabNavigationCoordinator.shared.showCollectionRoot()
            isAuthenticated = true
            // Bascule les stores isolés par compte (tags, journal d'écoute) sur ce compte : s'il
            // a déjà été utilisé sur cet appareil, ses données sont restaurées immédiatement.
            TagStore.shared.setActiveUsername(username)
            ListeningLogStore.shared.setActiveUsername(username)
            GradeStore.shared.setActiveUsername(username)
            ShelfPreferencesStore.shared.setActiveUsername(username)
            CloudSyncEngine.shared.setActiveUsername(username)
            WantlistAlertStore.shared.setActiveUsername(username)
            // Rejoue les actions hors ligne laissées en attente par ce compte lors d'une
            // session précédente (celles des autres comptes restent en file, voir `OfflineSyncQueue`).
            Task { await OfflineSyncQueue.shared.processQueue() }
            await fetchUserProfileIfNeeded(force: true)
        } catch {
            // Fenêtre de connexion fermée (ou « Annuler ») par l'utilisateur : un choix, pas une
            // erreur — rien à afficher, il peut simplement retoucher « Se connecter ».
            guard !Self.isUserCancellation(error) else { return }
            lastError = error.localizedDescription
        }
    }

    /// Vrai si l'utilisateur a lui-même interrompu la connexion (fermeture de la fenêtre
    /// d'autorisation, bouton « Annuler » de la demande d'accès à discogs.com).
    nonisolated static func isUserCancellation(_ error: Error) -> Bool {
        (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
    }

    /// Ouvre une session de démonstration sur la collection d'exemple (voir `DemoMode`).
    func startDemo() {
        guard !isAuthenticated else { return }
        DemoMode.setActive(true)
        DemoMode.applyPreferences()
        isDemoMode = true
        PremiumStore.shared.isDemoPreview = true
        lastError = nil
        username = DemoMode.username
        credentials = DemoMode.credentials
        TabNavigationCoordinator.shared.showCollectionRoot()
        isAuthenticated = true
        TagStore.shared.setActiveUsername(username)
        ListeningLogStore.shared.setActiveUsername(username)
        GradeStore.shared.setActiveUsername(username)
        ShelfPreferencesStore.shared.setActiveUsername(username)
        ListeningLogStore.shared.seedDemoSessions(DemoServer.exampleListeningSessions())
        WantlistAlertStore.shared.setActiveUsername(username)
    }

    func logout() {
        let wasDemo = isDemoMode
        keychain.remove(Keys.accessToken)
        keychain.remove(Keys.accessTokenSecret)
        keychain.remove(Keys.username)
        keychain.remove(Keys.avatarURL)
        // Avant de passer à `isAuthenticated = false` : la pile de Collection est recréée à ce
        // changement (voir `RootTabView`), elle doit l'être sans fiche déjà empilée.
        TabNavigationCoordinator.shared.resetNavigationPaths()
        isAuthenticated = false
        username = nil
        avatarURL = nil
        credentials = nil
        // Vide l'état en mémoire des stores isolés par compte (les données restent sur le
        // disque, prêtes à être restaurées si ce compte se reconnecte plus tard).
        TagStore.shared.setActiveUsername(nil)
        ListeningLogStore.shared.setActiveUsername(nil)
        GradeStore.shared.setActiveUsername(nil)
        ShelfPreferencesStore.shared.setActiveUsername(nil)
        CloudSyncEngine.shared.setActiveUsername(nil)
        WantlistAlertStore.shared.setActiveUsername(nil)
        // Idem pour Collection/Wantlist/Recherche : ces vues restent montées en permanence dans
        // le TabView racine, donc leurs singletons ne se réinitialisent jamais tout seuls entre
        // deux comptes. Sans ce vidage, les items du compte précédent restaient affichés après
        // connexion sur un autre compte et étaient même réécrits dans le cache local (SwiftData)
        // du nouveau compte au chargement suivant, car ce chargement fusionne avec l'existant
        // au lieu de le remplacer (voir `mergedWithFreshPage1`).
        CollectionViewModel.shared.reset()
        WantlistViewModel.shared.reset()
        SearchViewModel.shared.reset()
        LibraryMembershipStore.shared.refresh()
        // Les champs personnalisés en cache appartiennent au compte qu'on quitte.
        CollectionFieldsService.clearCache()
        // Vide la session web persistante des `SafariView` (fiches Discogs, marketplace...) :
        // sans ça, si l'utilisateur s'y était connecté manuellement, cette page resterait
        // connectée à ce compte même après connexion à un autre compte dans l'app.
        SafariView.clearPersistedDiscogsSession()
        // Évite que le widget "Album du jour" continue de piocher dans la collection d'un
        // compte dont on vient de se déconnecter.
        WidgetSnapshotStore.saveCollection([])
        // Sans ce rechargement, le widget gardait l'ancien disque affiché jusqu'à son prochain
        // rafraîchissement système (minuit) : vider l'instantané ne suffit pas.
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.randomAlbum)
        // La connexion Apple Music est un réglage device-wide (lié à MusicKit, pas à un compte
        // Discogs) : contrairement aux préférences de collection/rangement, qui sont propres à
        // ce compte et synchronisées via iCloud (donc déjà prêtes à être retrouvées à la
        // reconnexion ou sur un autre appareil), elle ne doit pas rester cochée pour le compte
        // Discogs suivant qui se connecterait sur cet appareil.
        AppleMusicAccountStore.shared.isConnected = false
        stopAccountBackgroundWork()

        // Contrairement à un vrai compte, rien de la démo n'est à conserver pour une reconnexion :
        // tags, écoutes et cache d'exemple sont effacés pour repartir de zéro la prochaine fois.
        if wasDemo {
            Self.clearDemoData()
            isDemoMode = false
            PremiumStore.shared.isDemoPreview = false
        }
    }

    /// Arrête tout ce qui travaille encore pour le compte qu'on quitte : sans ça, téléchargement
    /// hors ligne, résolution des années de master, classement des discographies, écoute en cours
    /// et lecture Apple Music continuaient après la déconnexion, avec les identifiants de ce compte.
    /// (Alertes wantlist et synchro iCloud s'arrêtent via leur `setActiveUsername(nil)`.)
    private func stopAccountBackgroundWork() {
        OfflineDownloadManager.shared.cancelDownload()
        Task { await MasterResolutionService.shared.cancel() }
        DiscogsCategoryBackfillService.shared.stop()
        AppleMusicPlaybackService.shared.stop()
        Task { await NowPlayingActivityManager.shared.endCurrentActivity() }
    }

    /// Efface tout ce que la démo a laissé sur l'appareil, à sa sortie ou au lancement suivant
    /// si l'app a été fermée en pleine démo.
    private static func clearDemoData() {
        LocalDataStore.shared.clearAllUserData(username: DemoMode.username)
        TagStore.shared.clearAccountData(for: DemoMode.username)
        ListeningLogStore.shared.clearAccountData(for: DemoMode.username)
        // Réglages de rangement de la démo : sinon ils revenaient à la démo suivante.
        ShelfPreferencesStore.shared.clearAccountData(for: DemoMode.username)
        BatchScanViewModel.clearDraft(for: DemoMode.username)
        // Alertes de prix et actions en file de la démo : sinon elles revenaient à la démo
        // suivante (et la file gardait des modifications impossibles à envoyer).
        WantlistAlertStore.shared.clearAccountData(for: DemoMode.username)
        OfflineSyncQueue.shared.removeActions(for: DemoMode.username)
        CollectionFieldsService.clearCache()
        OfflineDownloadManager.shared.resetOfflineState(for: DemoMode.username)
        // Sans ça, le widget continuait de proposer des disques de la démo après relancement.
        WidgetSnapshotStore.saveCollection([])
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.randomAlbum)
        DemoMode.setActive(false)
    }

    // MARK: - Suppression complète des données locales et cloud (Guideline 5.1.1(v))

    /// Supprime définitivement l'ensemble des données locales et synchronisées iCloud associées au compte connecté
    /// (cache SwiftData, tags, journal d'écoute, préférences, zone CloudKit) et déconnecte l'utilisateur.
    func deleteLocalAccountData() {
        // La démo n'a ni zone iCloud ni réglages propres : la quitter efface déjà tout.
        if isDemoMode {
            logout()
            return
        }
        if let currentUsername = username {
            // Synchro iCloud coupée AVANT d'effacer quoi que ce soit : vider les tags ou les
            // préférences signale un changement à envoyer, ce qui recréait aussitôt la zone
            // iCloud qu'on venait de demander de supprimer.
            CloudSyncEngine.shared.setActiveUsername(nil)
            CloudSyncEngine.shared.deleteCloudData(for: currentUsername)
            LocalDataStore.shared.clearAllUserData(username: currentUsername)
            TagStore.shared.clearAccountData(for: currentUsername)
            ListeningLogStore.shared.clearAccountData(for: currentUsername)
            GradeStore.shared.clearAccountData(for: currentUsername)
            ShelfPreferencesStore.shared.clearAccountData(for: currentUsername)
            BatchScanViewModel.clearDraft(for: currentUsername)
            WantlistAlertStore.shared.clearAccountData(for: currentUsername)
            OfflineSyncQueue.shared.removeActions(for: currentUsername)
            CollectionPreferencesStore.clearAccountData(for: currentUsername)
            OfflineDownloadManager.shared.resetOfflineState(for: currentUsername)
            // Pochettes téléchargées pour le mode hors ligne : elles ne sont pas rattachées à un
            // compte, donc le cache disque entier est vidé.
            KingfisherConfig.clearDiskCache()
            // Années et sections des masters Discogs : conservées sans limite jusque-là, elles
            // repartent aussi (elles seront re-résolues à la demande avec le prochain compte).
            LocalDataStore.shared.clearAllMasterYears()
            DiscogsWorkCategoryCache.shared.clearAll()
            DiscogsCategoryBackfillService.shared.clearHistory()
        }
        logout()
    }

    /// Récupère le profil public Discogs pour mettre à jour l'avatar de l'utilisateur.
    func fetchUserProfileIfNeeded(force: Bool = false) async {
        guard let username, let credentials else { return }
        if !force, avatarURL != nil { return }
        do {
            let profile = try await DiscogsAPIClient.shared.userProfile(username: username, credentials: credentials)
            if let avatar = profile.avatarURL, !avatar.isEmpty {
                self.avatarURL = avatar
                self.keychain.set(avatar, forKey: Keys.avatarURL)
            }
        } catch {
            // Échec réseau silencieux (mode hors-ligne ou rate limit)
        }
    }

    // MARK: - Étapes OAuth (réponses form-encoded, pas JSON)

    private func fetchRequestToken() async throws -> (token: String, secret: String) {
        let url = DiscogsConstants.apiBaseURL.appendingPathComponent("oauth/request_token")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(DiscogsSecrets.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            signer.authorizationHeader(
                method: "GET",
                url: url,
                additionalParameters: ["oauth_callback": callbackURL.absoluteString]
            ),
            forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response)
        let params = Self.parseFormBody(data)
        guard let token = params["oauth_token"], let secret = params["oauth_token_secret"] else {
            throw AuthError.invalidResponse
        }
        return (token, secret)
    }

    /// Code de vérification renvoyé par Discogs, seulement si le retour concerne bien la demande
    /// en cours (`oauth_token` identique) : un lien `spinlog://oauth-callback` forgé ailleurs ne peut
    /// alors pas faire valider une autre autorisation que celle que l'utilisateur vient d'accorder.
    nonisolated static func verifier(fromCallback callbackURL: URL?, requestToken: String) -> String? {
        guard let callbackURL,
              let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
              items.first(where: { $0.name == "oauth_token" })?.value == requestToken,
              let verifier = items.first(where: { $0.name == "oauth_verifier" })?.value,
              !verifier.isEmpty else {
            return nil
        }
        return verifier
    }

    private func authorize(requestToken: String) async throws -> String {
        guard var components = URLComponents(
            url: DiscogsConstants.websiteURL.appendingPathComponent("oauth/authorize"),
            resolvingAgainstBaseURL: false
        ) else { throw AuthError.invalidResponse }
        components.queryItems = [URLQueryItem(name: "oauth_token", value: requestToken)]
        guard let authorizeURL = components.url else { throw AuthError.invalidResponse }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: callbackURL.scheme
            ) { @Sendable callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let verifier = Self.verifier(fromCallback: callbackURL, requestToken: requestToken) else {
                    continuation.resume(throwing: AuthError.invalidResponse)
                    return
                }
                continuation.resume(returning: verifier)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            webAuthSession = session
            // Si la session ne peut pas démarrer, son completion handler n'est jamais appelé :
            // sans ce cas, la continuation restait en suspens et `isAuthenticating` bloqué à
            // `true`, rendant le bouton de connexion inopérant jusqu'au relancement de l'app.
            if !session.start() {
                webAuthSession = nil
                continuation.resume(throwing: AuthError.invalidResponse)
            }
        }
    }

    private func fetchAccessToken(
        requestToken: String,
        requestTokenSecret: String,
        verifier: String
    ) async throws -> (token: String, secret: String) {
        let url = DiscogsConstants.apiBaseURL.appendingPathComponent("oauth/access_token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(DiscogsSecrets.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            signer.authorizationHeader(
                method: "POST",
                url: url,
                token: requestToken,
                tokenSecret: requestTokenSecret,
                additionalParameters: ["oauth_verifier": verifier]
            ),
            forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response)
        let params = Self.parseFormBody(data)
        guard let token = params["oauth_token"], let secret = params["oauth_token_secret"] else {
            throw AuthError.invalidResponse
        }
        return (token, secret)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.invalidResponse
        }
    }

    private static func parseFormBody(_ data: Data) -> [String: String] {
        guard let string = String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for pair in string.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            result[key] = value
        }
        return result
    }

    enum AuthError: LocalizedError {
        case invalidResponse
        var errorDescription: String? { String(localized: "Impossible de se connecter à Discogs.") }
    }
}

extension DiscogsAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = windowScenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }
        // Ce delegate n'est appelé que pendant la présentation d'une session web, donc au moins
        // une scène existe à ce moment ; `ASPresentationAnchor()` sans scène est dépréciée.
        guard let scene = windowScenes.first else {
            preconditionFailure("Aucune scène connectée pour présenter la connexion Discogs")
        }
        return ASPresentationAnchor(windowScene: scene)
    }
}
