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

    /// Accès aux fonctions Premium, lu partout dans l'app. L'écriture (StoreKit, options
    /// développeur) ne modifie que l'abonnement réel.
    var isPremium: Bool {
        get { hasSubscription || isDemoPreview }
        set { hasSubscription = newValue }
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
