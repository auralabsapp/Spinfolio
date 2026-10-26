import SwiftUI

/// Actions "ajouter à la collection / à la wantlist" et état de possession, partagés entre
/// la recherche, le détail d'un master et le résultat de scan. Gère le mode hors ligne
/// avec mise en file d'attente (OfflineSyncQueue) et respect du mode lecture seule si TTL > 6h.
@Observable
@MainActor
final class ReleaseActions {
    var isUpdatingRating = false
    var message: String?
    /// Exemplaires présents dans la collection pour cette release (peut en contenir plusieurs).
    private(set) var collectionInstances: [CollectionItem] = []
    var instancesCount: Int { collectionInstances.count }
    private(set) var collectionFields: [CollectionField] = []
    /// Statut collection : modifiable instantanément en UI optimiste.
    private(set) var isInCollection = false
    /// Statut et actions wantlist de la release (voir `ReleaseWantlistActions`).
    private let wantlist = ReleaseWantlistActions()
    /// Statut wantlist : modifiable instantanément en UI optimiste.
    var isInWantlist: Bool { wantlist.isInWantlist }

    init() {
        // Messages et retours haptiques de la wantlist passent par ceux de la fiche.
        wantlist.report = { [weak self] in self?.message = $0 }
        wantlist.notifyFeedback = { [weak self] in self?.lastFeedbackEvent = LibraryFeedbackEvent($0) }
    }

    /// Dernier ajout/retrait fait par l'utilisateur (voir `LibraryFeedbackEvent`) : l'écran s'en sert
    /// pour le retour haptique et visuel.
    private(set) var lastFeedbackEvent: LibraryFeedbackEvent?

    /// ID de la release venant d'être ajoutée avec succès à la collection (pour proposer le guide de rangement)
    var justAddedReleaseId: Int? = nil

    /// Dossiers proposés lors de l'ajout (si l'utilisateur a plusieurs dossiers et souhaite en choisir un).
    private(set) var folders: [CollectionFolder] = []

    private let authManager = DiscogsAuthManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private let localStore = LocalDataStore.shared

    /// Renvoie le nom convivial du dossier pour un identifiant donné
    func folderName(for folderId: Int) -> String {
        folders.name(forFolderId: folderId)
    }

    /// Prépare instantanément l'état local depuis le cache SwiftData et la mémoire (0 ms de latence).
    func prepareInitialStatus(releaseId: Int) {
        guard let username = authManager.username else {
            collectionInstances = []
            isInCollection = false
            wantlist.prepare(releaseId: releaseId)
            return
        }

        // Lecture ciblée sur cette release : auparavant, toute la collection (puis toute la
        // wantlist) était décodée à chaque ouverture d'une fiche disque.
        let localInstances = localStore.getCollectionItems(username: username, releaseId: releaseId)
            .filter { $0.instanceId > 0 && $0.instanceId != $0.releaseId }
        if !localInstances.isEmpty {
            collectionInstances = localInstances
            isInCollection = true
        } else if LibraryMembershipStore.shared.isInCollection(releaseId) {
            isInCollection = true
        }

        wantlist.prepare(releaseId: releaseId)
    }

    /// Pré-charge les dossiers pour le sélecteur contextuel (voir `FolderPickerLoader`).
    func loadFoldersIfNeeded() async {
        guard let username = authManager.username,
              let loaded = await FolderPickerLoader.foldersForReleasePage(username: username) else { return }
        folders = loaded
    }

    /// Vérifie si la release est déjà dans la collection (et charge les champs personnalisés si oui).
    func checkIfInCollection(releaseId: Int) async {
        // 1. Initialisation immédiate depuis le cache local (0 ms)
        prepareInitialStatus(releaseId: releaseId)
        guard let username = authManager.username else { return }

        Task {
            await self.loadFoldersIfNeeded()
        }

        guard networkMonitor.isConnected, let credentials = authManager.credentials else { return }

        do {
            let instancesResponse = try await DiscogsAPIClient.shared.collectionInstances(
                username: username, releaseId: releaseId, credentials: credentials
            )
            let fetched = instancesResponse.releases.filter { $0.instanceId > 0 && $0.instanceId != $0.releaseId }
            collectionInstances = fetched
            isInCollection = !fetched.isEmpty
            if !fetched.isEmpty {
                await localStore.saveCollectionItems(fetched, username: username, folderId: DiscogsConstants.allFolderId)
                if collectionFields.isEmpty {
                    collectionFields = await CollectionFieldsService.fields(username: username, credentials: credentials)
                }
            }
        } catch {
            // En cas d'erreur réseau ou de limite de débit temporaire, on conserve le cache local
            if collectionInstances.isEmpty {
                isInCollection = false
            }
        }
    }

    /// Vérifie si la release est déjà dans la wantlist (voir `ReleaseWantlistActions`).
    func checkIfInWantlist(releaseId: Int) async {
        await wantlist.check(releaseId: releaseId)
    }

    /// Ajoute ou retire de la wantlist instantanément (grisé/dégrisé) au clic.
    func toggleWantlist(releaseId: Int, release: Release? = nil) async {
        await wantlist.toggle(releaseId: releaseId, release: release)
    }

    func addToWantlist(releaseId: Int, release: Release? = nil) async {
        await wantlist.add(releaseId: releaseId, release: release)
    }

    /// Reflète localement une note/des champs personnalisés déjà enregistrés par
    /// `CollectionItemEditSheet` (qui gère lui-même les appels réseau).
    /// La note (rating) est partagée par Discogs entre tous les exemplaires d'une même
    /// release : on la répercute donc sur tous les exemplaires locaux, alors que les champs
    /// personnalisés restent propres à l'exemplaire édité.
    func applyEditedValues(rating: Int, notes: [CollectionFieldValue], instanceId: Int? = nil) async {
        guard let username = authManager.username else { return }
        guard !collectionInstances.isEmpty else { return }

        for index in collectionInstances.indices {
            collectionInstances[index].rating = rating
        }
        if let instanceId, let index = collectionInstances.firstIndex(where: { $0.instanceId == instanceId }) {
            collectionInstances[index].notes = notes
        } else {
            collectionInstances[0].notes = notes
        }
        await saveInstancesToCache(username: username)
    }

    /// Met à jour la note personnelle de la release (partagée par Discogs entre tous les
    /// exemplaires possédés) : l'écriture se fait via n'importe quel exemplaire, puis la
    /// valeur est répercutée sur tous les exemplaires locaux.
    func updateReleaseRating(_ rating: Int) async {
        if DemoMode.isActive {
            message = AppMessages.demoModificationBlocked
            return
        }
        guard let username = authManager.username, let anchor = collectionInstances.first else { return }

        let previousInstances = collectionInstances
        isUpdatingRating = true
        defer { isUpdatingRating = false }
        for index in collectionInstances.indices {
            collectionInstances[index].rating = rating
        }
        // Hors ligne ou panne passagère : la note est gardée et part avec la file hors ligne,
        // comme les autres modifications (auparavant la saisie était perdue).
        switch await DiscogsWriteService.updateRating(rating, via: anchor, username: username) {
        case .refused:
            collectionInstances = previousInstances
            message = String(localized: "Impossible d'enregistrer la note sur Discogs.")
        case .done, .queuedOffline, .queuedAfterFailure:
            await saveInstancesToCache(username: username)
        }
    }

    private func saveInstancesToCache(username: String) async {
        for instance in collectionInstances {
            await localStore.saveCollectionItemInFolderAndAll(instance, username: username)
        }
    }

    // MARK: - Suivi de cote (prix d'achat)

    /// Écrit le prix d'achat sur un exemplaire précis. Contrairement à la note (partagée par
    /// Discogs entre tous les exemplaires d'une release), le prix d'achat est un champ personnalisé
    /// propre à chaque exemplaire physique : deux copies peuvent avoir été achetées à des prix différents.
    func updatePurchasePrice(_ canonicalValue: String, for instanceId: Int) async {
        if DemoMode.isActive {
            message = AppMessages.demoModificationBlocked
            return
        }
        guard let username = authManager.username,
              let fieldId = CollectionPreferencesStore.purchasePriceFieldId(for: username),
              let index = collectionInstances.firstIndex(where: { $0.instanceId == instanceId }) else { return }

        let instance = collectionInstances[index]
        collectionInstances[index].notes = instance.notes.settingValue(canonicalValue, forFieldId: fieldId)
        await localStore.saveCollectionItemInFolderAndAll(collectionInstances[index], username: username)

        // Hors ligne ou panne passagère : le prix reste affiché et part avec la file hors ligne
        // (champ propre à l'utilisateur, accepté même sur un cache ancien).
        let outcome = await DiscogsWriteService.updateField(fieldId, value: canonicalValue, of: instance, username: username)
        guard outcome == .refused,
              let current = collectionInstances.firstIndex(where: { $0.instanceId == instanceId }) else { return }
        collectionInstances[current].notes = instance.notes
        await localStore.saveCollectionItemInFolderAndAll(collectionInstances[current], username: username)
        message = String(localized: "Impossible d'enregistrer le prix d'achat sur Discogs.")
    }

    /// Écrit un champ personnalisé Discogs sur un exemplaire précis, dont l'appelant (ex:
    /// `CollectionItemEditSheet`) a déjà toutes les informations en main (pas besoin de les
    /// retrouver dans `collectionInstances`, contrairement à `updatePurchasePrice`) — il gère
    /// lui-même l'état optimiste et le mode hors ligne (file d'attente), propres à son écran.
    func updateCollectionField(folderId: Int, releaseId: Int, instanceId: Int, fieldId: Int, value: String) async throws {
        guard let (username, credentials) = authManager.session else { return }
        try await DiscogsWriteService.updateCollectionField(
            folderId: folderId, releaseId: releaseId, instanceId: instanceId,
            fieldId: fieldId, value: value, username: username, credentials: credentials
        )
    }

    /// Cote actuelle de la release (voir `MarketEstimateService`).
    func refreshMarketEstimateIfNeeded(releaseId: Int, condition: String?) async -> MarketEstimate? {
        await MarketEstimateService.estimate(releaseId: releaseId, condition: condition)
    }

    // MARK: - Collection

    /// Bascule instantanément l'état collection (grisé/dégrisé) au clic.
    func addToCollection(releaseId: Int, release: Release? = nil, targetFolderId: Int? = nil) async {
        if DemoMode.isActive {
            message = AppMessages.demoAddBlocked
            return
        }
        guard let username = authManager.username else {
            message = AppMessages.loginRequiredForCollection
            return
        }

        // Optimistic UI : griser instantanément le bouton
        withAnimation(.optimisticToggle) {
            isInCollection = true
            justAddedReleaseId = releaseId
        }
        lastFeedbackEvent = LibraryFeedbackEvent(.addedToCollection)

        let folderId = targetFolderId ?? CollectionPreferencesStore.folderIdForNewAddition(for: username)
        // Identifiant d'instance temporaire négatif pour l'optimistic UI (évite toute collision avec un vrai id Discogs)
        let tempInstanceId = DiscogsWriteService.makeTemporaryInstanceId()
        // Tags du nouvel exemplaire explicitement vides : il ne doit pas hériter de ceux d'une
        // autre version ou d'un exemplaire existant.
        TagStore.shared.setTags([], for: tempInstanceId)

        if let release {
            let item = CollectionItem(addedRelease: release, releaseId: releaseId, folderId: folderId, instanceId: tempInstanceId)
            collectionInstances.append(item)
            LibraryMembershipStore.shared.notifyCollectionItemAdded(item)
        } else {
            LibraryMembershipStore.shared.markInCollection(releaseId)
        }

        // Hors ligne avec des données de plus de 6 h : modifications bloquées.
        if !networkMonitor.isConnected && localStore.isCollectionStale(username: username, folderId: DiscogsConstants.allFolderId) {
            rollbackOptimisticAdd(tempInstanceId: tempInstanceId, releaseId: releaseId)
            if collectionInstances.isEmpty {
                LibraryMembershipStore.shared.notifyCollectionItemRemoved(releaseId: releaseId)
            }
            message = AppMessages.offlineStaleAddBlocked
            return
        }

        let (realInstanceId, outcome) = await DiscogsWriteService.addToCollection(
            releaseId: releaseId, folderId: folderId, temporaryInstanceId: tempInstanceId, username: username
        )
        switch outcome {
        case .done:
            guard let realInstanceId else { return }
            TagStore.shared.remapInstanceId(from: tempInstanceId, to: realInstanceId)
            if let release {
                let realItem = CollectionItem(addedRelease: release, releaseId: releaseId, folderId: folderId, instanceId: realInstanceId)
                if let index = collectionInstances.firstIndex(where: { $0.instanceId == tempInstanceId }) {
                    collectionInstances[index] = realItem
                }
                await localStore.saveCollectionItemInFolderAndAll(realItem, username: username)
                LibraryMembershipStore.shared.notifyCollectionInstanceReplaced(oldInstanceId: tempInstanceId, newInstance: realItem)
            }
            // Rafraîchir les informations des exemplaires en arrière-plan
            Task { await self.checkIfInCollection(releaseId: releaseId) }
        case .queuedOffline:
            // La bulle « Ajouté à la collection » précise que l'ajout n'atteindra Discogs qu'au
            // retour du réseau.
            LibraryMembershipStore.shared.noteQueuedOffline(.collectionAdded)
        case .queuedAfterFailure:
            message = AppMessages.discogsUnavailableQueued
        case .refused:
            // Refus définitif (release inexistante, identifiants invalides…) : un nouvel essai
            // échouerait à l'identique, l'ajout est annulé sans être mis en file.
            rollbackOptimisticAdd(tempInstanceId: tempInstanceId, releaseId: releaseId)
            LibraryMembershipStore.shared.notifyCollectionItemRemoved(releaseId: releaseId, instanceId: tempInstanceId)
            message = AppMessages.addFailed
        }
    }

    /// Annule l'exemplaire temporaire affiché par `addToCollection`.
    private func rollbackOptimisticAdd(tempInstanceId: Int, releaseId: Int) {
        TagStore.shared.removeTags(for: tempInstanceId)
        withAnimation(.optimisticToggle) {
            collectionInstances.removeAll { $0.instanceId == tempInstanceId }
            isInCollection = !collectionInstances.isEmpty
            if justAddedReleaseId == releaseId {
                justAddedReleaseId = nil
            }
        }
    }

    /// Supprime un exemplaire spécifique de la collection
    func removeInstance(_ instance: CollectionItem) async {
        if DemoMode.isActive {
            message = AppMessages.demoRemovalBlocked
            return
        }
        guard let username = authManager.username else { return }
        let releaseId = instance.releaseId

        let previousInstances = collectionInstances
        withAnimation(.optimisticToggle) {
            collectionInstances.removeAll { $0.instanceId == instance.instanceId }
            isInCollection = !collectionInstances.isEmpty
            if collectionInstances.isEmpty && justAddedReleaseId == releaseId {
                justAddedReleaseId = nil
            }
        }
        if collectionInstances.isEmpty {
            lastFeedbackEvent = LibraryFeedbackEvent(.removedFromCollection)
        }

        localStore.removeCollectionItemFromFolderAndAll(instance, username: username)
        if collectionInstances.isEmpty {
            localStore.removeCollectionItems(username: username, releaseId: releaseId)
            LibraryMembershipStore.shared.notifyCollectionItemRemoved(releaseId: releaseId)
        } else {
            LibraryMembershipStore.shared.notifyCollectionItemRemoved(releaseId: releaseId, instanceId: instance.instanceId)
        }

        // Un exemplaire ajouté hors ligne et pas encore envoyé n'existe pas sur Discogs : son
        // retrait (annulation de l'ajout en attente) n'est jamais bloqué hors ligne.
        if instance.instanceId > 0, !networkMonitor.isConnected,
           localStore.isCollectionStale(username: username, folderId: DiscogsConstants.allFolderId) {
            await restoreRemovedInstances([instance], previousInstances: previousInstances, username: username)
            message = AppMessages.offlineStaleRemovalBlocked
            return
        }

        switch await DiscogsWriteService.removeInstance(instance, username: username) {
        case .queuedOffline:
            LibraryMembershipStore.shared.noteQueuedOffline(.collectionRemoved)
        case .queuedAfterFailure:
            message = AppMessages.discogsUnavailableQueued
        case .refused:
            // Refus définitif : la file l'aurait retenté trois fois en vain avant d'afficher un
            // échec, pendant que l'UI montrait le disque comme retiré. On le restaure tout de suite.
            await restoreRemovedInstances([instance], previousInstances: previousInstances, username: username)
            message = AppMessages.removalFailed
        case .done:
            break
        }
    }

    /// Annule un retrait optimiste : réaffiche les exemplaires, les remet en cache (dans leur
    /// dossier ET dans "Tous") et prévient les autres écrans. Auparavant, le blocage hors ligne
    /// ne restaurait que ce view model : la liste de la collection, déjà prévenue du retrait,
    /// continuait d'afficher le disque comme retiré.
    private func restoreRemovedInstances(_ removed: [CollectionItem], previousInstances: [CollectionItem], username: String) async {
        withAnimation(.optimisticToggle) {
            collectionInstances = previousInstances
            isInCollection = !previousInstances.isEmpty
        }
        for instance in removed {
            await localStore.saveCollectionItemInFolderAndAll(instance, username: username)
            LibraryMembershipStore.shared.notifyCollectionItemAdded(instance)
        }
    }

    /// Déplace un exemplaire vers un autre dossier Discogs. Hors ligne, la modification est
    /// appliquée localement tout de suite et mise en file pour une synchro différée (même
    /// mécanique que `CollectionItemEditSheet` pour les champs personnalisés).
    func moveInstance(_ instance: CollectionItem, toFolderId: Int) async {
        if DemoMode.isActive {
            message = AppMessages.demoModificationBlocked
            return
        }
        guard let username = authManager.username, instance.folderId != toFolderId else { return }

        let movedItem = instance.moved(toFolderId: toFolderId)
        replaceInstance(instance.instanceId, with: movedItem)
        await localStore.replaceCollectionItemInCache(instance, with: movedItem, username: username)

        let outcome = await DiscogsWriteService.moveInstance(instance, toFolderId: toFolderId, username: username)
        if let queuedMessage = outcome.failureQueuedMessage {
            message = queuedMessage
        } else if outcome == .refused {
            // Refus définitif (exemplaire supprimé ailleurs, dossier inexistant…) : on remet
            // l'exemplaire dans son dossier d'origine plutôt que de laisser la file échouer trois
            // fois pendant que l'UI le montre déplacé.
            replaceInstance(instance.instanceId, with: instance)
            await localStore.replaceCollectionItemInCache(movedItem, with: instance, username: username)
            message = AppMessages.moveFailed
        }
    }

    private func replaceInstance(_ instanceId: Int, with item: CollectionItem) {
        withAnimation(.optimisticToggle) {
            if let index = collectionInstances.firstIndex(where: { $0.instanceId == instanceId }) {
                collectionInstances[index] = item
            }
        }
    }

    /// Supprime tous les exemplaires de la release de la collection
    func removeFromCollection(releaseId: Int) async {
        if DemoMode.isActive {
            message = AppMessages.demoRemovalBlocked
            return
        }
        guard let username = authManager.username else { return }

        let savedInstances = collectionInstances
        withAnimation(.optimisticToggle) {
            collectionInstances = []
            isInCollection = false
            if justAddedReleaseId == releaseId {
                justAddedReleaseId = nil
            }
        }
        lastFeedbackEvent = LibraryFeedbackEvent(.removedFromCollection)

        localStore.removeCollectionItems(username: username, releaseId: releaseId)
        LibraryMembershipStore.shared.notifyCollectionItemRemoved(releaseId: releaseId)

        if !networkMonitor.isConnected && localStore.isCollectionStale(username: username, folderId: DiscogsConstants.allFolderId) {
            await restoreRemovedInstances(savedInstances, previousInstances: savedInstances, username: username)
            if savedInstances.isEmpty {
                LibraryMembershipStore.shared.markInCollection(releaseId)
            }
            message = AppMessages.offlineStaleRemovalBlocked
            return
        }

        // Exemplaires ajoutés hors ligne et pas encore envoyés : leur ajout en attente est
        // annulé, au lieu de demander à Discogs de retirer un identifiant qui n'existe pas.
        let unsyncedInstances = savedInstances.filter { $0.instanceId < 0 }
        for instance in unsyncedInstances {
            _ = await DiscogsWriteService.removeInstance(instance, username: username)
        }
        let syncedInstances = savedInstances.filter { $0.instanceId > 0 }
        if !unsyncedInstances.isEmpty && syncedInstances.isEmpty {
            return
        }

        // Exemplaires à retirer : ceux connus localement, sinon ceux que Discogs renvoie.
        let (outcome, notRemoved) = await DiscogsWriteService.removeAllInstances(
            releaseId: releaseId, knownInstances: syncedInstances, username: username
        )
        switch outcome {
        case .queuedOffline:
            LibraryMembershipStore.shared.noteQueuedOffline(.collectionRemoved)
        case .queuedAfterFailure:
            message = AppMessages.discogsUnavailableQueued
        case .refused where notRemoved.isEmpty:
            // Exemplaires introuvables sur Discogs : le disque reste affiché comme possédé.
            LibraryMembershipStore.shared.markInCollection(releaseId)
            withAnimation(.optimisticToggle) {
                isInCollection = true
            }
            message = AppMessages.removalFailed
        case .refused:
            // Seuls les exemplaires pas encore retirés sont restaurés.
            await restoreRemovedInstances(notRemoved, previousInstances: notRemoved, username: username)
            message = AppMessages.removalFailed
        case .done:
            break
        }
    }
}
