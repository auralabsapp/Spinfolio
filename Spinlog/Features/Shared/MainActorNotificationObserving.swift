import Foundation

/// Raccourcis pour `NotificationCenter.default.addObserver(forName:object:queue:)` sur le thread
/// principal. Avant ce fichier, `CollectionViewModel`, `WantlistViewModel` et
/// `ArtistDetailViewModel` recopiaient chacun le même bloc `[weak self] notification in
/// MainActor.assumeIsolated { guard let self, ... else { return }; ... }`, avec des conventions de
/// cycle de vie différentes d'un fichier à l'autre (observateur jamais retiré vs retiré au
/// `deinit` via un tableau de tokens). Le token `NSObjectProtocol` renvoyé reste à la charge de
/// l'appelant : à ignorer pour un singleton qui vit toute la session, à collecter et retirer au
/// `deinit` pour une instance qui peut être désallouée (voir `ArtistDetailViewModel`).

/// Observateur sans charge utile (ex: "les préférences ont changé, recalcule").
@discardableResult
func addLibraryObserver(for name: Notification.Name, perform action: @escaping @MainActor () -> Void) -> NSObjectProtocol {
    NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated {
            action()
        }
    }
}

/// Observateur qui a besoin de plusieurs champs de `userInfo` (ex: `releaseId` + `instanceId`
/// optionnel) : reçoit la notification brute plutôt qu'une seule valeur typée.
@discardableResult
func addLibraryObserver(for name: Notification.Name, handling notification: @escaping @MainActor (Notification) -> Void) -> NSObjectProtocol {
    NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
        MainActor.assumeIsolated {
            notification(note)
        }
    }
}

/// Observateur avec une charge utile unique, typée, extraite de `userInfo[payloadKey]` — ignoré
/// silencieusement si absente ou du mauvais type (même comportement que le `guard` répété
/// manuellement à chaque appel avant ce helper).
@discardableResult
func addLibraryObserver<T>(for name: Notification.Name, payloadKey: String, perform action: @escaping @MainActor (T) -> Void) -> NSObjectProtocol {
    NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { notification in
        MainActor.assumeIsolated {
            guard let payload = notification.userInfo?[payloadKey] as? T else { return }
            action(payload)
        }
    }
}
