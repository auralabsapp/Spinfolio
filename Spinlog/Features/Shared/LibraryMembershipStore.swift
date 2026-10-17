import Foundation
import OSLog
import SwiftUI

private let membershipDebugLogger = Logger(subsystem: "com.aurelienscarpa.Spinlog", category: "LibrarySyncDebug")

extension Notification.Name {
    static let collectionItemAdded = Notification.Name("com.spinlog.collectionItemAdded")
    static let collectionItemRemoved = Notification.Name("com.spinlog.collectionItemRemoved")
    static let collectionInstanceReplaced = Notification.Name("com.spinlog.collectionInstanceReplaced")
    static let wantlistItemAdded = Notification.Name("com.spinlog.wantlistItemAdded")
    static let wantlistItemRemoved = Notification.Name("com.spinlog.wantlistItemRemoved")
}

/// Bulle de confirmation (façon Apple Music « Ajouté à la bibliothèque ») affichée après un
/// ajout/retrait collection/wantlist, quel que soit l'écran d'origine (résultats de recherche,
/// fiche release, fiche artiste, Collection, Wantlist...) — voir l'overlay global dans `RootTabView`.
enum LibraryToastKind: Equatable {
    case collectionAdded
    case collectionRemoved
    case wantlistAdded
    case wantlistRemoved

    var message: String {
        switch self {
        case .collectionAdded: String(localized: "Ajouté à la collection")
        case .collectionRemoved: String(localized: "Retiré de la collection")
        case .wantlistAdded: String(localized: "Ajouté à la wantlist")
        case .wantlistRemoved: String(localized: "Retiré de la wantlist")
        }
    }

    var systemImage: String {
        switch self {
        case .collectionAdded, .wantlistAdded: "checkmark.circle.fill"
        case .collectionRemoved, .wantlistRemoved: "minus.circle.fill"
        }
    }
}

/// Ensembles d'identifiants de releases déjà en collection / en wantlist, pour afficher des
/// pastilles dans les listes (résultats de recherche...) sans appel réseau dédié : on relit
/// simplement le cache SwiftData déjà maintenu à jour par les onglets Collection et Wantlist.
@Observable
@MainActor
final class LibraryMembershipStore {
    static let shared = LibraryMembershipStore()

    private(set) var collectionReleaseIds: Set<Int> = []
    private(set) var wantlistReleaseIds: Set<Int> = []

    private(set) var activeToast: LibraryToastKind?
    /// Incrémenté à chaque nouvelle bulle : permet à la tâche de disparition automatique de
    /// vérifier qu'aucune bulle plus récente n'a pris le relais avant de vider `activeToast`.
    private var toastGeneration = 0

    private let authManager = DiscogsAuthManager.shared
    private let localStore = LocalDataStore.shared

    private init() {}

    private func presentToast(_ kind: LibraryToastKind) {
        toastGeneration += 1
        let generation = toastGeneration
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            activeToast = kind
        }
        Task {
            try? await Task.sleep(for: AppTiming.toastDismissShort)
            guard generation == toastGeneration else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                activeToast = nil
            }
        }
    }

    /// Recharge les ensembles depuis le cache local. Le dossier `0` correspond au dossier
    /// virtuel Discogs "All", qui agrège l'ensemble de la collection.
    func refresh() {
        guard let username = authManager.username else {
            collectionReleaseIds = []
            wantlistReleaseIds = []
            return
        }
        // Lecture des seuls identifiants : auparavant, toute la collection et toute la wantlist
        // étaient décodées (JSON) à chaque affichage de l'onglet Recherche.
        collectionReleaseIds = localStore.collectionReleaseIds(username: username)
        wantlistReleaseIds = localStore.wantlistReleaseIds(username: username)
        // Le nombre suffit : la liste complète des identifiants, triée et concaténée, était
        // écrite dans les journaux à chaque appel, y compris en production.
        membershipDebugLogger.log("REFRESH collection=\(self.collectionReleaseIds.count) wantlist=\(self.wantlistReleaseIds.count)")
    }

    func isInCollection(_ releaseId: Int) -> Bool { collectionReleaseIds.contains(releaseId) }
    func isInWantlist(_ releaseId: Int) -> Bool { wantlistReleaseIds.contains(releaseId) }

    /// Mises à jour optimistes appelées directement par les actions d'ajout/retrait, car le
    /// cache local de Collection/Wantlist n'est réécrit qu'au prochain chargement de ces onglets.
    func markInCollection(_ releaseId: Int) { collectionReleaseIds.insert(releaseId) }
    func markRemovedFromCollection(_ releaseId: Int) { collectionReleaseIds.remove(releaseId) }
    func markInWantlist(_ releaseId: Int) { wantlistReleaseIds.insert(releaseId) }
    func markRemovedFromWantlist(_ releaseId: Int) { wantlistReleaseIds.remove(releaseId) }

    // MARK: - Notifications pour mise à jour immédiate des listes

    func notifyCollectionItemAdded(_ item: CollectionItem) {
        membershipDebugLogger.log("POST collectionItemAdded release=\(item.releaseId) instance=\(item.instanceId) folder=\(item.folderId)")
        markInCollection(item.releaseId)
        presentToast(.collectionAdded)
        NotificationCenter.default.post(
            name: .collectionItemAdded,
            object: nil,
            userInfo: ["item": item]
        )
    }

    func notifyCollectionInstanceReplaced(oldInstanceId: Int, newInstance: CollectionItem) {
        markInCollection(newInstance.releaseId)
        NotificationCenter.default.post(
            name: .collectionInstanceReplaced,
            object: nil,
            userInfo: [
                "oldInstanceId": oldInstanceId,
                "newItem": newInstance
            ]
        )
    }

    func notifyCollectionItemRemoved(releaseId: Int, instanceId: Int? = nil) {
        membershipDebugLogger.log("POST collectionItemRemoved release=\(releaseId) instance=\(instanceId ?? -1)")
        if let username = authManager.username {
            let stillOwned = localStore.hasOtherCollectionInstance(username: username, releaseId: releaseId, excludingInstanceId: instanceId)
            if !stillOwned {
                markRemovedFromCollection(releaseId)
            }
        } else {
            markRemovedFromCollection(releaseId)
        }
        presentToast(.collectionRemoved)
        var userInfo: [String: Any] = ["releaseId": releaseId]
        if let instanceId {
            userInfo["instanceId"] = instanceId
        }
        NotificationCenter.default.post(
            name: .collectionItemRemoved,
            object: nil,
            userInfo: userInfo
        )
    }

    func notifyWantlistItemAdded(_ item: WantlistItem) {
        membershipDebugLogger.log("POST wantlistItemAdded release=\(item.id)")
        markInWantlist(item.id)
        presentToast(.wantlistAdded)
        NotificationCenter.default.post(
            name: .wantlistItemAdded,
            object: nil,
            userInfo: ["item": item]
        )
    }

    func notifyWantlistItemRemoved(releaseId: Int) {
        membershipDebugLogger.log("POST wantlistItemRemoved release=\(releaseId) containedBefore=\(self.wantlistReleaseIds.contains(releaseId))")
        markRemovedFromWantlist(releaseId)
        membershipDebugLogger.log("POST wantlistItemRemoved release=\(releaseId) containedAfter=\(self.wantlistReleaseIds.contains(releaseId))")
        presentToast(.wantlistRemoved)
        NotificationCenter.default.post(
            name: .wantlistItemRemoved,
            object: nil,
            userInfo: ["releaseId": releaseId]
        )
    }
}
