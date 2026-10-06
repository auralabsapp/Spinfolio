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

    private let storageKey = "com.spinlog.isPremium"

    /// Stocké dans l'App Group partagé (plutôt que `.standard`) pour que l'extension de
    /// widgets puisse lire le statut premium sans mécanisme de synchronisation séparé.
    private let defaults = UserDefaults(suiteName: "group.com.auralabs.Spinlog") ?? .standard

    var isPremium: Bool {
        didSet {
            guard isPremium != oldValue else { return }
            defaults.set(isPremium, forKey: storageKey)
            if !isPremium {
                ThemeManager.shared.revertToDefaultIfNeeded(isPremium: false)
            }
            NotificationCenter.default.post(name: .premiumStatusChanged, object: nil)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.randomAlbum)
        }
    }

    private init() {
        let groupDefaults = UserDefaults(suiteName: "group.com.auralabs.Spinlog") ?? .standard
        if groupDefaults.object(forKey: storageKey) == nil, UserDefaults.standard.object(forKey: storageKey) != nil {
            // Migration ponctuelle depuis l'ancien emplacement (avant l'introduction de l'App Group).
            groupDefaults.set(UserDefaults.standard.bool(forKey: storageKey), forKey: storageKey)
        }
        isPremium = groupDefaults.bool(forKey: storageKey)
        // Réécrit systématiquement (même valeur) à chaque lancement : ça garantit qu'un widget
        // qui ne verrait jamais rien (App Group cassé/mal provisionné) est détectable en
        // distinguant "clé absente" de "clé présente valant false", plutôt que de dépendre du
        // seul `didSet`, qui ne s'écrit qu'au premier changement volontaire de l'utilisateur.
        groupDefaults.set(isPremium, forKey: storageKey)

        if !isPremium {
            ThemeManager.shared.revertToDefaultIfNeeded(isPremium: false)
        }
    }
}
