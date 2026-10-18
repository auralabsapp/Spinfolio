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

/// Boîte observable individuelle pour une release : permet à `@Observable` de suivre la
/// mutation du statut d'UNE seule release sans invalider tous les lecteurs de
/// `LibraryMembershipStore` — même principe que `WantlistAlertBox`. Avant cette boîte, le statut
/// était stocké dans deux `Set<Int>` observés en bloc : ajouter/retirer N'IMPORTE QUELLE release
/// (depuis n'importe quel écran) réinvalidait TOUTES les lignes ayant appelé `isInCollection`/
/// `isInWantlist`, pas seulement celle dont le statut changeait réellement (résultats de
/// recherche, scan par lot...).
@MainActor
@Observable
final class ReleaseMembershipBox {
    var inCollection: Bool
    var inWantlist: Bool
    init(inCollection: Bool = false, inWantlist: Bool = false) {
        self.inCollection = inCollection
        self.inWantlist = inWantlist
    }
}

/// Statut (collection / wantlist) de chaque release, pour afficher des pastilles dans les listes
/// (résultats de recherche...) sans appel réseau dédié : on relit simplement le cache SwiftData
/// déjà maintenu à jour par les onglets Collection et Wantlist.
@Observable
@MainActor
final class LibraryMembershipStore {
    static let shared = LibraryMembershipStore()

    private(set) var boxes: [Int: ReleaseMembershipBox] = [:]

    private(set) var activeToast: LibraryToastKind?
    /// La bulle affichée concerne une action mise en file hors ligne : elle l'indique sur une
    /// deuxième ligne (au lieu d'une alerte à fermer après chaque ajout ou retrait hors ligne).
    private(set) var activeToastIsQueuedOffline = false
    /// Incrémenté à chaque nouvelle bulle : permet à la tâche de disparition automatique de
    /// vérifier qu'aucune bulle plus récente n'a pris le relais avant de vider `activeToast`.
    private var toastGeneration = 0

    private let authManager = DiscogsAuthManager.shared
    private let localStore = LocalDataStore.shared

    private init() {}

    private func presentToast(_ kind: LibraryToastKind, queuedOffline: Bool = false) {
        toastGeneration += 1
        let generation = toastGeneration
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            activeToast = kind
            activeToastIsQueuedOffline = queuedOffline
        }
        Task {
            try? await Task.sleep(for: AppTiming.toastDismissShort)
            guard generation == toastGeneration else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                activeToast = nil
            }
        }
    }

    /// Action enregistrée hors ligne (file `OfflineSyncQueue`) : complète la bulle déjà affichée
    /// pour cette action, ou l'affiche si l'écran d'origine n'en montre pas (retrait par balayage…).
    func noteQueuedOffline(_ kind: LibraryToastKind) {
        if activeToast == kind {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                activeToastIsQueuedOffline = true
            }
        } else {
            presentToast(kind, queuedOffline: true)
        }
    }

    /// Recharge les ensembles depuis le cache local. Le dossier `0` correspond au dossier
    /// virtuel Discogs "All", qui agrège l'ensemble de la collection.
    func refresh() {
        guard let username = authManager.username else {
            boxes = [:]
            return
        }
        // Lecture des seuls identifiants : auparavant, toute la collection et toute la wantlist
        // étaient décodées (JSON) à chaque affichage de l'onglet Recherche.
        let freshCollectionIds = localStore.collectionReleaseIds(username: username)
        let freshWantlistIds = localStore.wantlistReleaseIds(username: username)

        // Mutation en place des boîtes existantes (n'invalide que leurs propres lecteurs) plutôt
        // que de réassigner `boxes` en bloc à chaque refresh — seules les créations/suppressions
        // de clé ci-dessous (releases jamais vues ou qui sortent des deux listes) invalident
        // l'ensemble des lecteurs, et ça reste rare comparé aux refresh eux-mêmes.
        for id in freshCollectionIds.union(freshWantlistIds) {
            let inCollection = freshCollectionIds.contains(id)
            let inWantlist = freshWantlistIds.contains(id)
            if let box = boxes[id] {
                if box.inCollection != inCollection { box.inCollection = inCollection }
                if box.inWantlist != inWantlist { box.inWantlist = inWantlist }
            } else {
                boxes[id] = ReleaseMembershipBox(inCollection: inCollection, inWantlist: inWantlist)
            }
        }
        // Nettoyage des boîtes devenues obsolètes (ni en collection, ni en wantlist), pour ne pas
        // accumuler indéfiniment des entrées mortes au fil des sessions.
        for id in boxes.keys where !freshCollectionIds.contains(id) && !freshWantlistIds.contains(id) {
            boxes.removeValue(forKey: id)
        }
        // Le nombre suffit : la liste complète des identifiants, triée et concaténée, était
        // écrite dans les journaux à chaque appel, y compris en production.
        membershipDebugLogger.log("REFRESH collection=\(freshCollectionIds.count) wantlist=\(freshWantlistIds.count)")
    }

    func isInCollection(_ releaseId: Int) -> Bool { boxes[releaseId]?.inCollection ?? false }
    func isInWantlist(_ releaseId: Int) -> Bool { boxes[releaseId]?.inWantlist ?? false }

    /// Boîte existante pour cette release, ou nouvellement créée si c'est la première fois
    /// qu'on en a besoin. Ne crée (donc ne mute `boxes` lui-même, qui invalide tout le monde)
    /// que pour une release jamais rencontrée jusqu'ici — un retrait (`markRemoved...`) n'a lui
    /// jamais besoin de créer de boîte, voir plus bas.
    private func box(for releaseId: Int) -> ReleaseMembershipBox {
        if let existing = boxes[releaseId] { return existing }
        let newBox = ReleaseMembershipBox()
        boxes[releaseId] = newBox
        return newBox
    }

    /// Mises à jour optimistes appelées directement par les actions d'ajout/retrait, car le
    /// cache local de Collection/Wantlist n'est réécrit qu'au prochain chargement de ces onglets.
    /// Chacune ne mute que le champ concerné d'UNE boîte : seuls les lecteurs de cette release
    /// précise sont invalidés, pas toutes les lignes de la liste affichée.
    func markInCollection(_ releaseId: Int) { box(for: releaseId).inCollection = true }
    func markRemovedFromCollection(_ releaseId: Int) { boxes[releaseId]?.inCollection = false }
    func markInWantlist(_ releaseId: Int) { box(for: releaseId).inWantlist = true }
    func markRemovedFromWantlist(_ releaseId: Int) { boxes[releaseId]?.inWantlist = false }

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
        membershipDebugLogger.log("POST wantlistItemRemoved release=\(releaseId) containedBefore=\(self.isInWantlist(releaseId))")
        markRemovedFromWantlist(releaseId)
        membershipDebugLogger.log("POST wantlistItemRemoved release=\(releaseId) containedAfter=\(self.isInWantlist(releaseId))")
        presentToast(.wantlistRemoved)
        NotificationCenter.default.post(
            name: .wantlistItemRemoved,
            object: nil,
            userInfo: ["releaseId": releaseId]
        )
    }
}
