import SwiftUI

/// Actions "ajouter à la collection / à la wantlist" et état de possession, partagés entre
/// la recherche, le détail d'un master et le résultat de scan. Gère le mode hors ligne
/// avec mise en file d'attente (OfflineSyncQueue) et respect du mode lecture seule si TTL > 6h.
@Observable
@MainActor
final class ReleaseActions {
    var isWorking = false
    var isUpdatingRating = false
    var message: String?
    /// Exemplaires présents dans la collection pour cette release (peut en contenir plusieurs).
    private(set) var collectionInstances: [CollectionItem] = []
    var collectionInstance: CollectionItem? { collectionInstances.first }
    var instancesCount: Int { collectionInstances.count }
    private(set) var collectionFields: [CollectionField] = []
    /// Statut collection : modifiable instantanément en UI optimiste.
    private(set) var isInCollection = false
    /// Statut wantlist : modifiable instantanément en UI optimiste.
    private(set) var isInWantlist = false

    /// ID de la release venant d'être ajoutée avec succès à la collection (pour proposer le guide de rangement)
    var justAddedReleaseId: Int? = nil

    /// Dossiers proposés lors de l'ajout (si l'utilisateur a plusieurs dossiers et souhaite en choisir un).
    private(set) var folders: [CollectionFolder] = []

    static var cachedCollectionFields: [CollectionField] = []

    private let authManager = DiscogsAuthManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private let localStore = LocalDataStore.shared
    private let syncQueue = OfflineSyncQueue.shared

    /// Point d'accès partagé par toute l'app aux champs personnalisés Discogs (dossiers,
    /// prix d'achat, état du média...), pour éviter que chaque écran (collection, réglages,
    /// édition d'un exemplaire...) ne refasse le même appel réseau indépendamment. Le cache
    /// n'expire pas en mémoire pour la durée de vie du process : ces champs ne changent que
    /// si l'utilisateur en crée/modifie sur discogs.com, ce qui est rare.
    static func fetchCollectionFields(username: String, credentials: DiscogsCredentials?) async -> [CollectionField] {
        if !cachedCollectionFields.isEmpty {
            return cachedCollectionFields
        }
        guard let credentials,
              let response = try? await DiscogsAPIClient.shared.collectionFields(username: username, credentials: credentials) else {
            return []
        }
        cachedCollectionFields = response.fields
        return response.fields
    }

    /// Renvoie le nom convivial du dossier pour un identifiant donné
    func folderName(for folderId: Int) -> String {
        if let folder = folders.first(where: { $0.id == folderId }) {
            return folder.name
        }
        if folderId == DiscogsConstants.uncategorizedFolderId {
            return "Uncategorized"
        }
        return "Dossier \(folderId)"
    }

    /// Prépare instantanément l'état local depuis le cache SwiftData et la mémoire (0 ms de latence).
    func prepareInitialStatus(releaseId: Int) {
        guard let username = authManager.username else {
            collectionInstances = []
            isInCollection = false
            isInWantlist = false
            return
        }

        let cached = localStore.getCollectionItems(username: username, folderId: DiscogsConstants.allFolderId)
        let localInstances = cached.filter { $0.releaseId == releaseId && $0.instanceId > 0 && $0.instanceId != $0.releaseId }
        if !localInstances.isEmpty {
            collectionInstances = localInstances
            isInCollection = true
        } else if LibraryMembershipStore.shared.isInCollection(releaseId) {
            isInCollection = true
        }

        if LibraryMembershipStore.shared.isInWantlist(releaseId) ||
           localStore.getWantlistItems(username: username).contains(where: { $0.id == releaseId }) {
            isInWantlist = true
        }
    }

    /// Pré-charge les dossiers pour le sélecteur contextuel
    func loadFoldersIfNeeded() async {
        guard let username = authManager.username else { return }
        let result = await FolderPickerLoader.loadFolders(
            username: username,
            networkMonitor: networkMonitor,
            localStore: localStore,
            credentials: authManager.credentials
        )
        if case .success(let fetched) = result, !fetched.isEmpty {
            folders = fetched
        }
    }

    /// Vérifie si la release est déjà dans la collection (et charge les champs personnalisés si oui).
    func checkIfInCollection(releaseId: Int) async {
        guard let username = authManager.username else {
            collectionInstances = []
            isInCollection = false
            return
        }

        // 1. Initialisation immédiate depuis le cache local (0 ms)
        prepareInitialStatus(releaseId: releaseId)

        Task {
            await self.loadFoldersIfNeeded()
        }

        if !networkMonitor.isConnected {
            return
        }

        guard let credentials = authManager.credentials else { return }

        do {
            let instancesResponse = try await DiscogsAPIClient.shared.collectionInstances(
                username: username, releaseId: releaseId, credentials: credentials
            )
            let fetched = instancesResponse.releases.filter { $0.instanceId > 0 && $0.instanceId != $0.releaseId }
            collectionInstances = fetched
            isInCollection = !fetched.isEmpty
            if !fetched.isEmpty {
                localStore.saveCollectionItems(fetched, username: username, folderId: DiscogsConstants.allFolderId)
                if collectionFields.isEmpty {
                    collectionFields = await Self.fetchCollectionFields(username: username, credentials: credentials)
                }
            }
        } catch {
            // En cas d'erreur réseau ou de limite de débit temporaire, on conserve le cache local
            if collectionInstances.isEmpty {
                isInCollection = false
            }
        }
    }

    /// Vérifie si la release est déjà dans la wantlist.
    func checkIfInWantlist(releaseId: Int) async {
        guard let username = authManager.username else {
            isInWantlist = false
            return
        }

        // 1. Initialisation immédiate depuis le cache local
        if LibraryMembershipStore.shared.isInWantlist(releaseId) ||
           localStore.getWantlistItems(username: username).contains(where: { $0.id == releaseId }) {
            isInWantlist = true
        }

        if !networkMonitor.isConnected {
            return
        }

        guard let credentials = authManager.credentials else { return }

        do {
            _ = try await DiscogsAPIClient.shared.wantlistItem(username: username, releaseId: releaseId, credentials: credentials)
            isInWantlist = true
        } catch {
            // Un 404 est une confirmation explicite et fiable du serveur ("absente de la
            // wantlist") : elle doit l'emporter sur le cache local, qui peut être resté
            // fantôme si sa purge a échoué (voir `LocalDataStore.syncWantlist`). Les autres
            // erreurs (réseau, 5xx...) sont ambiguës : on garde alors l'état local optimiste
            // plutôt que de faire disparaître le bouton à tort sur un simple aléa réseau.
            if case DiscogsAPIClient.APIError.http(404, _) = error {
                isInWantlist = false
            } else if !LibraryMembershipStore.shared.isInWantlist(releaseId) {
                isInWantlist = false
            }
        }
    }

    /// Reflète localement une note/des champs personnalisés déjà enregistrés par
    /// `CollectionItemEditSheet` (qui gère lui-même les appels réseau).
    /// La note (rating) est partagée par Discogs entre tous les exemplaires d'une même
    /// release : on la répercute donc sur tous les exemplaires locaux, alors que les champs
    /// personnalisés restent propres à l'exemplaire édité.
    func applyEditedValues(rating: Int, notes: [CollectionFieldValue], instanceId: Int? = nil) {
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

        for instance in collectionInstances {
            localStore.saveCollectionItems([instance], username: username, folderId: instance.folderId)
            localStore.saveCollectionItems([instance], username: username, folderId: DiscogsConstants.allFolderId)
        }
    }

    /// Met à jour la note personnelle de la release (partagée par Discogs entre tous les
    /// exemplaires possédés) : l'écriture se fait via n'importe quel exemplaire, puis la
    /// valeur est répercutée sur tous les exemplaires locaux.
    func updateReleaseRating(_ rating: Int) async {
        guard let (username, credentials) = authManager.session,
              let anchor = collectionInstances.first else { return }

        let previousInstances = collectionInstances
        isUpdatingRating = true
        for index in collectionInstances.indices {
            collectionInstances[index].rating = rating
        }

        do {
            try await DiscogsAPIClient.shared.updateCollectionRating(
                username: username,
                folderId: anchor.folderId,
                releaseId: anchor.releaseId,
                instanceId: anchor.instanceId,
                rating: rating,
                credentials: credentials
            )
            for instance in collectionInstances {
                localStore.saveCollectionItems([instance], username: username, folderId: instance.folderId)
                localStore.saveCollectionItems([instance], username: username, folderId: DiscogsConstants.allFolderId)
            }
        } catch {
            collectionInstances = previousInstances
            message = "Impossible d'enregistrer la note sur Discogs."
        }
        isUpdatingRating = false
    }

    // MARK: - Suivi de cote (prix d'achat)

    /// Écrit le prix d'achat sur un exemplaire précis. Contrairement à la note (partagée par
    /// Discogs entre tous les exemplaires d'une release), le prix d'achat est un champ personnalisé
    /// propre à chaque exemplaire physique : deux copies peuvent avoir été achetées à des prix différents.
    func updatePurchasePrice(_ canonicalValue: String, for instanceId: Int) async {
        guard let (username, credentials) = authManager.session,
              let fieldId = CollectionPreferencesStore.purchasePriceFieldId(for: username),
              let index = collectionInstances.firstIndex(where: { $0.instanceId == instanceId }) else { return }

        let instance = collectionInstances[index]
        let previousNotes = instance.notes

        var updatedNotes = instance.notes
        if let noteIndex = updatedNotes.firstIndex(where: { $0.fieldId == fieldId }) {
            updatedNotes[noteIndex] = CollectionFieldValue(fieldId: fieldId, value: canonicalValue)
        } else {
            updatedNotes.append(CollectionFieldValue(fieldId: fieldId, value: canonicalValue))
        }
        collectionInstances[index].notes = updatedNotes
        localStore.saveCollectionItems([collectionInstances[index]], username: username, folderId: instance.folderId)
        localStore.saveCollectionItems([collectionInstances[index]], username: username, folderId: DiscogsConstants.allFolderId)

        do {
            try await DiscogsAPIClient.shared.updateCollectionField(
                username: username,
                folderId: instance.folderId,
                releaseId: instance.releaseId,
                instanceId: instance.instanceId,
                fieldId: fieldId,
                value: canonicalValue,
                credentials: credentials
            )
        } catch {
            collectionInstances[index].notes = previousNotes
            localStore.saveCollectionItems([collectionInstances[index]], username: username, folderId: instance.folderId)
            localStore.saveCollectionItems([collectionInstances[index]], username: username, folderId: DiscogsConstants.allFolderId)
            message = "Impossible d'enregistrer le prix d'achat sur Discogs."
        }
    }

    /// Estimation de la cote actuelle d'une release, à partir des suggestions de prix Discogs
    /// pour l'état renseigné (ou de leur moyenne si l'état est inconnu/non trouvé). Throttlé via
    /// `ReleasePriceSnapshot` : renvoie immédiatement la dernière valeur connue si elle date de
    /// moins de 6h (les CGU de l'API Discogs interdisent d'afficher du Content de plus de 6h),
    /// ou en cas d'absence de réseau — sauf si l'état déclaré a changé depuis ce dernier calcul,
    /// auquel cas le cache est invalidé pour refléter tout de suite le nouvel état (l'estimation
    /// dépend directement de l'état saisi).
    func refreshMarketEstimateIfNeeded(releaseId: Int, condition: String?) async -> (price: Double, currency: String)? {
        let freshnessWindow: TimeInterval = DiscogsConstants.sixHoursTTL

        if let cached = localStore.latestReleasePriceSnapshot(releaseId: releaseId),
           cached.condition == condition,
           Date().timeIntervalSince(cached.date) < freshnessWindow {
            return (cached.medianPrice, cached.currency)
        }

        guard networkMonitor.isConnected, let credentials = authManager.credentials else {
            if let cached = localStore.latestReleasePriceSnapshot(releaseId: releaseId) {
                return (cached.medianPrice, cached.currency)
            }
            return nil
        }

        guard let suggestions = try? await DiscogsAPIClient.shared.priceSuggestions(releaseId: releaseId, credentials: credentials),
              !suggestions.isEmpty else {
            return nil
        }

        let estimate: MarketplacePrice
        if let condition, let matched = suggestions[condition] {
            estimate = matched
        } else {
            // Moyenne des suggestions disponibles : Discogs renvoie systématiquement toutes les
            // suggestions d'une même release dans une seule et même devise.
            let currency = suggestions.values.first?.currency ?? "USD"
            let average = suggestions.values.map(\.value).reduce(0, +) / Double(suggestions.count)
            estimate = MarketplacePrice(currency: currency, value: average)
        }

        localStore.saveReleasePriceSnapshot(releaseId: releaseId, currency: estimate.currency, medianPrice: estimate.value, condition: condition)
        return (estimate.value, estimate.currency)
    }

    // MARK: - Collection Toggle & Actions

    /// Bascule instantanément l'état collection (grisé/dégrisé) au clic.
    func addToCollection(releaseId: Int, release: Release? = nil, targetFolderId: Int? = nil) async {
        guard let username = authManager.username else {
            message = AppMessages.loginRequiredForCollection
            return
        }

        // Optimistic UI : griser instantanément le bouton
        withAnimation(.easeInOut(duration: 0.2)) {
            isInCollection = true
            justAddedReleaseId = releaseId
        }

        let folderId: Int
        if let targetFolderId {
            folderId = targetFolderId
        } else {
            let defaultId = CollectionPreferencesStore.defaultAddFolderId(for: username)
            if defaultId != CollectionPreferencesStore.alwaysAskFolderId {
                folderId = defaultId
            } else if let lastFolderId = CollectionPreferencesStore.lastConsultedFolderId(for: username), lastFolderId > 0 {
                folderId = lastFolderId
            } else {
                folderId = DiscogsConstants.uncategorizedFolderId
            }
        }

        // Identifiant d'instance temporaire négatif pour l'optimistic UI (évite toute collision avec un vrai id Discogs)
        let tempInstanceId = -Int(Date().timeIntervalSince1970)

        // Initialise explicitement les tags de ce nouvel exemplaire à vide
        // pour garantir qu'il n'hérite pas des tags d'une version ou d'un exemplaire existant
        TagStore.shared.setTags([], for: tempInstanceId)

        if let release {
            let item = CollectionItem(
                releaseId: releaseId,
                folderId: folderId,
                rating: 0,
                dateAdded: ISO8601DateFormatter().string(from: Date()),
                basicInformation: release.basicInformation,
                instanceId: tempInstanceId,
                notes: []
            )
            collectionInstances.append(item)
            LibraryMembershipStore.shared.notifyCollectionItemAdded(item)
        } else {
            LibraryMembershipStore.shared.markInCollection(releaseId)
        }

        // Si hors ligne et données de plus de 6h (Option B) : blocage des modifications
        if !networkMonitor.isConnected && localStore.isCollectionStale(username: username, folderId: DiscogsConstants.allFolderId) {
            TagStore.shared.removeTags(for: tempInstanceId)
            withAnimation(.easeInOut(duration: 0.2)) {
                collectionInstances.removeAll { $0.instanceId == tempInstanceId }
                isInCollection = !collectionInstances.isEmpty
                if justAddedReleaseId == releaseId {
                    justAddedReleaseId = nil
                }
            }
            if collectionInstances.isEmpty {
                LibraryMembershipStore.shared.notifyCollectionItemRemoved(releaseId: releaseId)
            }
            message = AppMessages.offlineStaleAddBlocked
            return
        }

        if !networkMonitor.isConnected {
            let action = PendingAction(type: .addToCollection, releaseId: releaseId, folderId: folderId)
            syncQueue.enqueue(action)
            return
        }

        guard let credentials = authManager.credentials else { return }
        do {
            let response = try await DiscogsAPIClient.shared.addToCollection(
                username: username, folderId: folderId, releaseId: releaseId, credentials: credentials
            )
            let realInstanceId = response.instanceId
            TagStore.shared.remapInstanceId(from: tempInstanceId, to: realInstanceId)
            if let release {
                let realItem = CollectionItem(
                    releaseId: releaseId,
                    folderId: folderId,
                    rating: 0,
                    dateAdded: ISO8601DateFormatter().string(from: Date()),
                    basicInformation: release.basicInformation,
                    instanceId: realInstanceId,
                    notes: []
                )
                if let idx = collectionInstances.firstIndex(where: { $0.instanceId == tempInstanceId }) {
                    collectionInstances[idx] = realItem
                }
                localStore.saveCollectionItems([realItem], username: username, folderId: folderId)
                localStore.saveCollectionItems([realItem], username: username, folderId: DiscogsConstants.allFolderId)
                LibraryMembershipStore.shared.notifyCollectionInstanceReplaced(oldInstanceId: tempInstanceId, newInstance: realItem)
            }
            // Rafraîchir les informations des exemplaires en arrière-plan
            Task {
                await self.checkIfInCollection(releaseId: releaseId)
            }
        } catch {
            TagStore.shared.removeTags(for: tempInstanceId)
            withAnimation(.easeInOut(duration: 0.2)) {
                collectionInstances.removeAll { $0.instanceId == tempInstanceId }
                isInCollection = !collectionInstances.isEmpty
                if justAddedReleaseId == releaseId {
                    justAddedReleaseId = nil
                }
            }
            LibraryMembershipStore.shared.notifyCollectionItemRemoved(releaseId: releaseId, instanceId: tempInstanceId)
            let action = PendingAction(type: .addToCollection, releaseId: releaseId, folderId: folderId)
            syncQueue.enqueue(action)
        }
    }

    /// Supprime un exemplaire spécifique de la collection
    func removeInstance(_ instance: CollectionItem) async {
        guard let username = authManager.username else { return }

        let targetInstanceId = instance.instanceId
        let targetFolderId = instance.folderId
        let releaseId = instance.releaseId

        let previousInstances = collectionInstances
        withAnimation(.easeInOut(duration: 0.2)) {
            collectionInstances.removeAll { $0.instanceId == targetInstanceId }
            isInCollection = !collectionInstances.isEmpty
            if collectionInstances.isEmpty && justAddedReleaseId == releaseId {
                justAddedReleaseId = nil
            }
        }

        localStore.removeCollectionItem(username: username, folderId: targetFolderId, instanceId: targetInstanceId)
        localStore.removeCollectionItem(username: username, folderId: DiscogsConstants.allFolderId, instanceId: targetInstanceId)

        if collectionInstances.isEmpty {
            localStore.removeCollectionItems(username: username, releaseId: releaseId)
            LibraryMembershipStore.shared.notifyCollectionItemRemoved(releaseId: releaseId)
        } else {
            LibraryMembershipStore.shared.notifyCollectionItemRemoved(releaseId: releaseId, instanceId: targetInstanceId)
        }

        if !networkMonitor.isConnected && localStore.isCollectionStale(username: username, folderId: DiscogsConstants.allFolderId) {
            withAnimation(.easeInOut(duration: 0.2)) {
                collectionInstances = previousInstances
                isInCollection = !previousInstances.isEmpty
            }
            localStore.saveCollectionItems([instance], username: username, folderId: targetFolderId)
            localStore.saveCollectionItems([instance], username: username, folderId: DiscogsConstants.allFolderId)
            message = AppMessages.offlineStaleRemovalBlocked
            return
        }

        if !networkMonitor.isConnected {
            let action = PendingAction(
                type: .removeFromCollection,
                releaseId: releaseId,
                folderId: targetFolderId,
                instanceId: targetInstanceId
            )
            syncQueue.enqueue(action)
            return
        }

        guard let credentials = authManager.credentials else { return }
        do {
            try await DiscogsAPIClient.shared.removeFromCollection(
                username: username,
                folderId: targetFolderId,
                releaseId: releaseId,
                instanceId: targetInstanceId,
                credentials: credentials
            )
        } catch {
            let action = PendingAction(
                type: .removeFromCollection,
                releaseId: releaseId,
                folderId: targetFolderId,
                instanceId: targetInstanceId
            )
            syncQueue.enqueue(action)
        }
    }

    /// Déplace un exemplaire vers un autre dossier Discogs. Hors ligne, la modification est
    /// appliquée localement tout de suite et mise en file pour une synchro différée (même
    /// mécanique que `CollectionItemEditSheet` pour les champs personnalisés).
    func moveInstance(_ instance: CollectionItem, toFolderId: Int) async {
        guard let username = authManager.username, instance.folderId != toFolderId else { return }

        let instanceId = instance.instanceId
        let releaseId = instance.releaseId
        let originFolderId = instance.folderId

        let movedItem = CollectionItem(
            releaseId: instance.releaseId,
            folderId: toFolderId,
            rating: instance.rating,
            dateAdded: instance.dateAdded,
            basicInformation: instance.basicInformation,
            instanceId: instance.instanceId,
            notes: instance.notes
        )

        withAnimation(.easeInOut(duration: 0.2)) {
            if let idx = collectionInstances.firstIndex(where: { $0.instanceId == instanceId }) {
                collectionInstances[idx] = movedItem
            }
        }

        localStore.removeCollectionItem(username: username, folderId: originFolderId, instanceId: instanceId)
        localStore.saveCollectionItems([movedItem], username: username, folderId: toFolderId)
        localStore.saveCollectionItems([movedItem], username: username, folderId: DiscogsConstants.allFolderId)
        LibraryMembershipStore.shared.notifyCollectionInstanceReplaced(oldInstanceId: instanceId, newInstance: movedItem)

        if !networkMonitor.isConnected {
            syncQueue.enqueue(PendingAction(
                type: .moveCollectionInstance,
                releaseId: releaseId,
                folderId: originFolderId,
                instanceId: instanceId,
                targetFolderId: toFolderId
            ))
            return
        }

        guard let credentials = authManager.credentials else { return }
        do {
            try await DiscogsAPIClient.shared.moveCollectionInstance(
                username: username,
                folderId: originFolderId,
                releaseId: releaseId,
                instanceId: instanceId,
                toFolderId: toFolderId,
                credentials: credentials
            )
        } catch {
            syncQueue.enqueue(PendingAction(
                type: .moveCollectionInstance,
                releaseId: releaseId,
                folderId: originFolderId,
                instanceId: instanceId,
                targetFolderId: toFolderId
            ))
        }
    }

    /// Supprime tous les exemplaires de la release de la collection
    func removeFromCollection(releaseId: Int) async {
        guard let username = authManager.username else { return }

        let savedInstances = collectionInstances
        withAnimation(.easeInOut(duration: 0.2)) {
            collectionInstances = []
            isInCollection = false
            if justAddedReleaseId == releaseId {
                justAddedReleaseId = nil
            }
        }

        localStore.removeCollectionItems(username: username, releaseId: releaseId)
        LibraryMembershipStore.shared.notifyCollectionItemRemoved(releaseId: releaseId)

        if !networkMonitor.isConnected && localStore.isCollectionStale(username: username, folderId: DiscogsConstants.allFolderId) {
            withAnimation(.easeInOut(duration: 0.2)) {
                collectionInstances = savedInstances
                isInCollection = !savedInstances.isEmpty
            }
            if !savedInstances.isEmpty {
                localStore.saveCollectionItems(savedInstances, username: username, folderId: DiscogsConstants.allFolderId)
                for inst in savedInstances {
                    LibraryMembershipStore.shared.notifyCollectionItemAdded(inst)
                }
            } else {
                LibraryMembershipStore.shared.markInCollection(releaseId)
            }
            message = AppMessages.offlineStaleRemovalBlocked
            return
        }

        if !networkMonitor.isConnected {
            for inst in savedInstances {
                let action = PendingAction(
                    type: .removeFromCollection,
                    releaseId: releaseId,
                    folderId: inst.folderId,
                    instanceId: inst.instanceId
                )
                syncQueue.enqueue(action)
            }
            return
        }

        guard let credentials = authManager.credentials else { return }
        do {
            if savedInstances.isEmpty {
                let fetched = try await DiscogsAPIClient.shared.collectionInstances(
                    username: username, releaseId: releaseId, credentials: credentials
                )
                for inst in fetched.releases {
                    try await DiscogsAPIClient.shared.removeFromCollection(
                        username: username,
                        folderId: inst.folderId,
                        releaseId: releaseId,
                        instanceId: inst.instanceId,
                        credentials: credentials
                    )
                }
            } else {
                for inst in savedInstances {
                    try await DiscogsAPIClient.shared.removeFromCollection(
                        username: username,
                        folderId: inst.folderId,
                        releaseId: releaseId,
                        instanceId: inst.instanceId,
                        credentials: credentials
                    )
                }
            }
        } catch {
            for inst in savedInstances {
                let action = PendingAction(
                    type: .removeFromCollection,
                    releaseId: releaseId,
                    folderId: inst.folderId,
                    instanceId: inst.instanceId
                )
                syncQueue.enqueue(action)
            }
        }
    }

    // MARK: - Wantlist Toggle & Actions

    /// Ajoute ou retire de la wantlist instantanément (grisé/dégrisé) au clic.
    func toggleWantlist(releaseId: Int, release: Release? = nil) async {
        if isInWantlist {
            await removeFromWantlist(releaseId: releaseId)
        } else {
            await addToWantlist(releaseId: releaseId, release: release)
        }
    }

    func addToWantlist(releaseId: Int, release: Release? = nil) async {
        guard let username = authManager.username else {
            message = AppMessages.loginRequiredForWantlist
            return
        }

        // Optimistic UI : griser instantanément le bouton
        withAnimation(.easeInOut(duration: 0.2)) {
            isInWantlist = true
        }

        if let release {
            let item = WantlistItem(
                id: releaseId,
                rating: 0,
                notes: nil,
                dateAdded: ISO8601DateFormatter().string(from: Date()),
                basicInformation: release.basicInformation
            )
            localStore.saveWantlistItems([item], username: username)
            LibraryMembershipStore.shared.notifyWantlistItemAdded(item)
        } else {
            LibraryMembershipStore.shared.markInWantlist(releaseId)
        }

        // Si hors ligne et données de plus de 6h : blocage
        if !networkMonitor.isConnected && localStore.isWantlistStale(username: username) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isInWantlist = false
            }
            localStore.removeWantlistItem(username: username, releaseId: releaseId)
            LibraryMembershipStore.shared.notifyWantlistItemRemoved(releaseId: releaseId)
            message = AppMessages.offlineStaleAddBlocked
            return
        }

        if !networkMonitor.isConnected {
            let action = PendingAction(type: .addToWantlist, releaseId: releaseId)
            syncQueue.enqueue(action)
            return
        }

        guard let credentials = authManager.credentials else { return }
        do {
            _ = try await DiscogsAPIClient.shared.addToWantlist(username: username, releaseId: releaseId, credentials: credentials)
        } catch {
            let action = PendingAction(type: .addToWantlist, releaseId: releaseId)
            syncQueue.enqueue(action)
        }
    }

    func removeFromWantlist(releaseId: Int) async {
        guard let username = authManager.username else { return }

        // Optimistic UI : dégriser instantanément le bouton
        withAnimation(.easeInOut(duration: 0.2)) {
            isInWantlist = false
        }
        localStore.removeWantlistItem(username: username, releaseId: releaseId)
        LibraryMembershipStore.shared.notifyWantlistItemRemoved(releaseId: releaseId)

        if !networkMonitor.isConnected && localStore.isWantlistStale(username: username) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isInWantlist = true
            }
            LibraryMembershipStore.shared.markInWantlist(releaseId)
            message = AppMessages.offlineStaleRemovalBlocked
            return
        }

        if !networkMonitor.isConnected {
            let action = PendingAction(type: .removeFromWantlist, releaseId: releaseId)
            syncQueue.enqueue(action)
            return
        }

        guard let credentials = authManager.credentials else { return }
        do {
            _ = try await DiscogsAPIClient.shared.removeFromWantlist(username: username, releaseId: releaseId, credentials: credentials)
        } catch {
            let action = PendingAction(type: .removeFromWantlist, releaseId: releaseId)
            syncQueue.enqueue(action)
        }
    }
}
