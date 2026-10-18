import Foundation
import MusicKit
import Observation

/// Statut de connexion au compte Apple Music de l'appareil (autorisation + abonnement actif),
/// configuré dans Réglages et consulté par `AppleMusicPlaybackService` pour choisir entre l'extrait
/// de 30s et la lecture complète d'un titre depuis une fiche release.
/// Le réglage `isConnected` est stocké uniquement en local dans `UserDefaults` (pas de synchronisation iCloud).
@MainActor
@Observable
final class AppleMusicAccountStore {
    static let shared = AppleMusicAccountStore()

    private let isConnectedKey = "appleMusicAccountConnected"

    /// Réglage stocké uniquement en local dans `UserDefaults` (non synchronisé sur iCloud).
    /// Par défaut décoché (`false`).
    var isConnected: Bool {
        didSet {
            UserDefaults.standard.set(isConnected, forKey: isConnectedKey)
            if isConnected {
                Task { await connect() }
            }
        }
    }

    private(set) var isAuthorized: Bool
    private(set) var hasActiveSubscription: Bool = false
    private(set) var isChecking: Bool = false

    /// Lecture complète du catalogue : nécessite que la case soit cochée, l'autorisation accordée
    /// ET un abonnement Apple Music actif. Sans l'un des trois, on retombe sur l'extrait de 30s.
    var canPlayFullCatalog: Bool {
        isConnected && isAuthorized && hasActiveSubscription
    }

    private init() {
        self.isConnected = UserDefaults.standard.bool(forKey: isConnectedKey)
        self.isAuthorized = MusicAuthorization.currentStatus == .authorized
        if isConnected {
            Task { await refreshSubscriptionStatus() }
        }
    }

    /// Déclenché quand l'utilisateur coche la case pour connecter son compte.
    func connect() async {
        isChecking = true
        defer { isChecking = false }

        _ = await ensureAuthorizationRequested()
        await refreshSubscriptionStatus()
    }

    /// Déclenche l'invite système si elle n'a encore jamais été présentée et renvoie si
    /// l'autorisation est accordée.
    func ensureAuthorizationRequested() async -> Bool {
        if MusicAuthorization.currentStatus == .notDetermined {
            isAuthorized = await MusicAuthorization.request() == .authorized
        } else {
            isAuthorized = MusicAuthorization.currentStatus == .authorized
        }
        return isAuthorized
    }

    private func refreshSubscriptionStatus() async {
        guard isAuthorized else {
            hasActiveSubscription = false
            return
        }
        do {
            let subscription = try await MusicSubscription.current
            hasActiveSubscription = subscription.canPlayCatalogContent
        } catch {
            hasActiveSubscription = false
        }
    }
}
