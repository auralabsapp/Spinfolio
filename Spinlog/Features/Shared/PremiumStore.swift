import Foundation
import Observation
import WidgetKit

extension Notification.Name {
    static let premiumStatusChanged = Notification.Name("com.spinlog.premiumStatusChanged")
}

/// Statut premium de l'utilisateur, stocké localement sur l'appareil.
///
/// Ce store ne gère pour l'instant aucun achat in-app ni vérification serveur : il s'agit
/// uniquement d'un interrupteur préparant le terrain pour le déblocage de fonctionnalités
/// premium à venir (le reste de l'app peut déjà lire `PremiumStore.shared.isPremium` pour
/// conditionner l'accès à ces fonctionnalités).
@Observable
@MainActor
final class PremiumStore {
    static let shared = PremiumStore()

    private let storageKey = PremiumConstants.isPremiumDefaultsKey

    /// Stocké dans l'App Group partagé (plutôt que `.standard`) pour que l'extension de
    /// widgets puisse lire le statut premium sans mécanisme de synchronisation séparé.
    private let defaults = UserDefaults(suiteName: AppGroup.id) ?? .standard

    /// Abonnement réellement actif (StoreKit, ou interrupteur développeur en debug) : seule
    /// valeur persistée, et celle à lire pour décider s'il faut proposer l'offre (paywall,
    /// bannière de Réglages).
    var hasSubscription: Bool {
        didSet {
            guard hasSubscription != oldValue else { return }
            defaults.set(hasSubscription, forKey: storageKey)
            premiumAccessDidChange()
        }
    }

    /// Aperçu Premium offert pendant la démo (voir `DemoMode`) : jamais persisté ni partagé avec
    /// le widget, il disparaît dès qu'on quitte la démo.
    var isDemoPreview: Bool = false {
        didSet {
            guard isDemoPreview != oldValue else { return }
            premiumAccessDidChange()
        }
    }

    #if DEBUG
    /// Forçage « Compte Premium » des options développeur (builds de développement uniquement).
    /// Distinct de l'abonnement réel : auparavant, l'interrupteur écrivait dans `hasSubscription`
    /// et StoreKit n'avait plus le droit de le remettre à `false`, si bien qu'un abonnement de
    /// test expiré laissait le Premium actif dans les builds lancés depuis Xcode.
    var developerOverride: Bool {
        didSet {
            guard developerOverride != oldValue else { return }
            UserDefaults.standard.set(developerOverride, forKey: Self.developerOverrideKey)
            premiumAccessDidChange()
        }
    }

    private static let developerOverrideKey = "com.spinlog.debug.premiumOverride"
    #endif

    /// Accès aux fonctions Premium, lu partout dans l'app : abonnement réel, aperçu de la démo,
    /// ou forçage développeur (Debug).
    var isPremium: Bool {
        #if DEBUG
        hasSubscription || isDemoPreview || developerOverride
        #else
        hasSubscription || isDemoPreview
        #endif
    }

    /// Premium hors aperçu de la démo (abonnement, ou forçage développeur en Debug) : sert à
    /// repérer le passage au Premium, qui réactive la synchronisation iCloud.
    var hasAccessOutsideDemo: Bool {
        #if DEBUG
        hasSubscription || developerOverride
        #else
        hasSubscription
        #endif
    }

    /// Premium offert seulement par la démo : les fonctions Premium y portent une étiquette
    /// (`DemoPremiumBadge`) pour montrer ce que l'abonnement apporte.
    var showsDemoPremiumBadges: Bool {
        isDemoPreview && !hasSubscription
    }

    private func premiumAccessDidChange() {
        if !isPremium {
            ThemeManager.shared.revertToDefaultIfNeeded(isPremium: false)
        }
        NotificationCenter.default.post(name: .premiumStatusChanged, object: nil)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.randomAlbum)
    }

    private init() {
        let groupDefaults = UserDefaults(suiteName: AppGroup.id) ?? .standard
        if groupDefaults.object(forKey: storageKey) == nil, UserDefaults.standard.object(forKey: storageKey) != nil {
            // Migration ponctuelle depuis l'ancien emplacement (avant l'introduction de l'App Group).
            groupDefaults.set(UserDefaults.standard.bool(forKey: storageKey), forKey: storageKey)
        }
        hasSubscription = groupDefaults.bool(forKey: storageKey)
        #if DEBUG
        developerOverride = UserDefaults.standard.bool(forKey: Self.developerOverrideKey)
        #endif
        // Réécrit systématiquement (même valeur) à chaque lancement : ça garantit qu'un widget
        // qui ne verrait jamais rien (App Group cassé/mal provisionné) est détectable en
        // distinguant "clé absente" de "clé présente valant false", plutôt que de dépendre du
        // seul `didSet`, qui ne s'écrit qu'au premier changement volontaire de l'utilisateur.
        groupDefaults.set(hasSubscription, forKey: storageKey)

        if !isPremium {
            ThemeManager.shared.revertToDefaultIfNeeded(isPremium: false)
        }
    }
}
