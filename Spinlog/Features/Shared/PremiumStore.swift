import Foundation
import Observation

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

    var isPremium: Bool {
        didSet {
            guard isPremium != oldValue else { return }
            UserDefaults.standard.set(isPremium, forKey: storageKey)
            NotificationCenter.default.post(name: .premiumStatusChanged, object: nil)
        }
    }

    private init() {
        isPremium = UserDefaults.standard.bool(forKey: storageKey)
    }
}
