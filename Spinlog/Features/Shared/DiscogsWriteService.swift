import Foundation

/// Suite d'une écriture vers Discogs déjà affichée à l'écran (mise à jour optimiste).
enum DiscogsWriteOutcome: Equatable {
    /// Envoyée, ou déjà effective (retrait d'un élément absent de Discogs, exemplaire ajouté hors
    /// ligne dont l'ajout en attente a été annulé ou redirigé).
    case done
    /// Hors ligne (ou identifiants Discogs pas encore disponibles) : mise en file, rejouée au
    /// retour du réseau avec les identifiants du compte.
    case queuedOffline
    /// Discogs injoignable ou quota dépassé : mise en file comme hors ligne.
    case queuedAfterFailure
    /// Refus définitif (un nouvel essai échouerait à l'identique) : l'appelant restaure l'état.
    case refused

    /// Message à afficher quand l'écriture part en file faute de Discogs.
    var failureQueuedMessage: String? {
        self == .queuedAfterFailure ? AppMessages.discogsUnavailableQueued : nil
    }
}

/// Envoi vers Discogs des écritures de la Collection et de la Wantlist, avec repli sur la file
/// hors ligne (`OfflineSyncQueue`) : hors ligne, sans identifiants ou panne passagère → en file,
/// refus définitif → `.refused`. Rien n'est jamais abandonné en silence. Sans état :
/// les view models (`CollectionViewModel`, `ReleaseActions`) gardent la mise à jour optimiste et
/// la restauration ; ils vérifient le mode démo et l'état hors ligne périmé avant d'appeler.
enum DiscogsWriteService {
    private static var syncQueue: OfflineSyncQueue { .shared }
    private static var isConnected: Bool { NetworkMonitor.shared.isConnected }
    private static var credentials: DiscogsCredentials? { DiscogsAuthManager.shared.credentials }

    // MARK: - Collection

    /// Ajoute un disque au dossier. `temporaryInstanceId` (négatif) identifie l'exemplaire affiché
    /// en attendant : la file le retrouve si l'exemplaire est retiré ou déplacé avant la synchro.
    /// - Returns: l'identifiant d'exemplaire créé par Discogs, ou la suite donnée sinon.
    static func addToCollection(
        releaseId: Int,
        folderId: Int,
        temporaryInstanceId: Int,
        username: String
    ) async -> (instanceId: Int?, outcome: DiscogsWriteOutcome) {
        let action = PendingAction(type: .addToCollection, releaseId: releaseId, folderId: folderId, instanceId: temporaryInstanceId)
        guard isConnected, let credentials else {
            syncQueue.enqueue(action)
            return (nil, .queuedOffline)
        }
        do {
            let response = try await DiscogsAPIClient.shared.addToCollection(
                username: username, folderId: folderId, releaseId: releaseId, credentials: credentials
            )
            return (response.instanceId, .done)
        } catch where error.isTransientNetworkFailure {
            // L'exemplaire optimiste reste affiché : le mettre en file ET annuler l'ajout à
            // l'écran (comme autrefois) poussait à réessayer, et finissait en double.
            syncQueue.enqueue(action)
            return (nil, .queuedAfterFailure)
        } catch {
            return (nil, .refused)
        }
    }

    /// Retire un exemplaire. Un exemplaire ajouté hors ligne et pas encore envoyé n'existe pas
    /// sur Discogs : son ajout en attente est simplement annulé.
    static func removeInstance(_ item: CollectionItem, username: String) async -> DiscogsWriteOutcome {
        if item.instanceId < 0 {
            syncQueue.cancelPendingAdd(temporaryInstanceId: item.instanceId)
            TagStore.shared.removeTags(for: item.instanceId)
            return .done
        }
        let action = PendingAction(type: .removeFromCollection, releaseId: item.releaseId, folderId: item.folderId, instanceId: item.instanceId)
        guard isConnected, let credentials else {
            syncQueue.enqueue(action)
            return .queuedOffline
        }
        do {
            try await DiscogsAPIClient.shared.removeFromCollection(
                username: username, folderId: item.folderId, releaseId: item.releaseId,
                instanceId: item.instanceId, credentials: credentials
            )
            return .done
        } catch where error.isNotFound {
            // Déjà absent sur Discogs (supprimé ailleurs) : le retrait est acquis.
            return .done
        } catch where error.isTransientNetworkFailure {
            syncQueue.enqueue(action)
            return .queuedAfterFailure
        } catch {
            return .refused
        }
    }

    /// Retire tous les exemplaires synchronisés d'un disque, un par un. S'il n'en connaît aucun,
    /// demande d'abord à Discogs lesquels existent.
    /// - Returns: la suite donnée et, en cas d'échec, les exemplaires pas encore retirés
    ///   (mis en file si l'échec est passager, à restaurer s'il est définitif).
    static func removeAllInstances(
        releaseId: Int,
        knownInstances: [CollectionItem],
        username: String
    ) async -> (outcome: DiscogsWriteOutcome, notRemoved: [CollectionItem]) {
        guard isConnected, let credentials else {
            for instance in knownInstances {
                syncQueue.enqueue(PendingAction(type: .removeFromCollection, releaseId: releaseId, folderId: instance.folderId, instanceId: instance.instanceId))
            }
            return (.queuedOffline, [])
        }

        var targets = knownInstances
        if targets.isEmpty {
            do {
                targets = try await DiscogsAPIClient.shared.collectionInstances(
                    username: username, releaseId: releaseId, credentials: credentials
                ).releases
            } catch where error.isTransientNetworkFailure {
                // Sans `instanceId`, la file récupère elle-même l'exemplaire (et refuse de choisir
                // s'il y en a plusieurs). Auparavant, rien n'était mis en file dans ce cas.
                syncQueue.enqueue(PendingAction(type: .removeFromCollection, releaseId: releaseId))
                return (.queuedAfterFailure, [])
            } catch {
                return (.refused, [])
            }
        }

        // Un par un : en cas d'échec, seuls les exemplaires restants sont mis en file ou
        // restaurés (auparavant, tous l'étaient, y compris ceux déjà retirés).
        for (index, instance) in targets.enumerated() {
            do {
                try await DiscogsAPIClient.shared.removeFromCollection(
                    username: username, folderId: instance.folderId, releaseId: releaseId,
                    instanceId: instance.instanceId, credentials: credentials
                )
            } catch where error.isNotFound {
                continue
            } catch {
                let remaining = Array(targets[index...])
                guard error.isTransientNetworkFailure else { return (.refused, remaining) }
                for instance in remaining {
                    syncQueue.enqueue(PendingAction(type: .removeFromCollection, releaseId: releaseId, folderId: instance.folderId, instanceId: instance.instanceId))
                }
                return (.queuedAfterFailure, remaining)
            }
        }
        return (.done, [])
    }

    /// Déplace un exemplaire. Pour un exemplaire ajouté hors ligne, seul le dossier de son ajout
    /// en attente change (il n'existe pas encore sur Discogs).
    static func moveInstance(_ item: CollectionItem, toFolderId: Int, username: String) async -> DiscogsWriteOutcome {
        if item.instanceId < 0 {
            syncQueue.retargetPendingAdd(temporaryInstanceId: item.instanceId, toFolderId: toFolderId)
            return .done
        }
        let action = PendingAction(
            type: .moveCollectionInstance, releaseId: item.releaseId, folderId: item.folderId,
            instanceId: item.instanceId, targetFolderId: toFolderId
        )
        guard isConnected, let credentials else {
            syncQueue.enqueue(action)
            return .queuedOffline
        }
        do {
            try await DiscogsAPIClient.shared.moveCollectionInstance(
                username: username, folderId: item.folderId, releaseId: item.releaseId,
                instanceId: item.instanceId, toFolderId: toFolderId, credentials: credentials
            )
            return .done
        } catch where error.isTransientNetworkFailure {
            syncQueue.enqueue(action)
            return .queuedAfterFailure
        } catch {
            return .refused
        }
    }

    /// Note (étoiles) d'une release, écrite via l'un de ses exemplaires (Discogs la partage entre
    /// tous). Hors ligne ou panne passagère : la note est gardée et part avec la file hors ligne.
    static func updateRating(_ rating: Int, via instance: CollectionItem, username: String) async -> DiscogsWriteOutcome {
        let action = PendingAction(
            type: .updateCollectionRating, releaseId: instance.releaseId, folderId: instance.folderId,
            instanceId: instance.instanceId, value: String(rating)
        )
        return await send(action) { credentials in
            try await DiscogsAPIClient.shared.updateCollectionRating(
                username: username, folderId: instance.folderId, releaseId: instance.releaseId,
                instanceId: instance.instanceId, rating: rating, credentials: credentials
            )
        }
    }

    /// Champ personnalisé d'un exemplaire (prix d'achat…), avec le même repli sur la file : ce
    /// sont des données de l'utilisateur, acceptées même sur un cache ancien.
    static func updateField(_ fieldId: Int, value: String, of instance: CollectionItem, username: String) async -> DiscogsWriteOutcome {
        let action = PendingAction(
            type: .updateCollectionField, releaseId: instance.releaseId, folderId: instance.folderId,
            instanceId: instance.instanceId, fieldId: fieldId, value: value
        )
        return await send(action) { credentials in
            try await updateCollectionField(
                folderId: instance.folderId, releaseId: instance.releaseId, instanceId: instance.instanceId,
                fieldId: fieldId, value: value, username: username, credentials: credentials
            )
        }
    }

    /// Écriture directe d'un champ personnalisé, sans file : l'appelant (`CollectionItemEditSheet`)
    /// gère lui-même l'état optimiste et le mode hors ligne, propres à son écran.
    static func updateCollectionField(
        folderId: Int, releaseId: Int, instanceId: Int, fieldId: Int, value: String,
        username: String, credentials: DiscogsCredentials
    ) async throws {
        try await DiscogsAPIClient.shared.updateCollectionField(
            username: username, folderId: folderId, releaseId: releaseId,
            instanceId: instanceId, fieldId: fieldId, value: value, credentials: credentials
        )
    }

    // MARK: - Wantlist

    static func addToWantlist(releaseId: Int, username: String) async -> DiscogsWriteOutcome {
        await sendWantlistChange(.addToWantlist, releaseId: releaseId) { credentials in
            _ = try await DiscogsAPIClient.shared.addToWantlist(username: username, releaseId: releaseId, credentials: credentials)
        }
    }

    static func removeFromWantlist(releaseId: Int, username: String) async -> DiscogsWriteOutcome {
        await sendWantlistChange(.removeFromWantlist, releaseId: releaseId) { credentials in
            do {
                _ = try await DiscogsAPIClient.shared.removeFromWantlist(username: username, releaseId: releaseId, credentials: credentials)
            } catch where error.isNotFound {
                // Déjà absent de la wantlist sur Discogs : le retrait est acquis.
            }
        }
    }

    private static func sendWantlistChange(
        _ type: ActionType,
        releaseId: Int,
        request: (DiscogsCredentials) async throws -> Void
    ) async -> DiscogsWriteOutcome {
        await send(PendingAction(type: type, releaseId: releaseId), request: request)
    }

    /// Envoi direct si connecté, sinon mise en file ; panne passagère → en file, refus → `.refused`
    /// (une annulation compte comme un refus : rien n'est mis en file).
    private static func send(_ action: PendingAction, request: (DiscogsCredentials) async throws -> Void) async -> DiscogsWriteOutcome {
        guard isConnected, let credentials else {
            syncQueue.enqueue(action)
            return .queuedOffline
        }
        do {
            try await request(credentials)
            return .done
        } catch where error.isTransientNetworkFailure && !error.isCancellation {
            syncQueue.enqueue(action)
            return .queuedAfterFailure
        } catch {
            return .refused
        }
    }

    // MARK: - Exemplaires temporaires

    private static var lastTemporaryInstanceId = 0

    /// Identifiant négatif unique pour un exemplaire en cours d'ajout. L'ancien `-timestamp` à la
    /// seconde près donnait le même identifiant à deux ajouts rapprochés (scan en lot), qui
    /// partageaient alors tags, remplacement et retrait. Strictement décroissant ici.
    static func makeTemporaryInstanceId() -> Int {
        let candidate = -Int(Date().timeIntervalSince1970 * 1000)
        lastTemporaryInstanceId = min(candidate, lastTemporaryInstanceId - 1)
        return lastTemporaryInstanceId
    }
}

extension LocalDataStore {
    /// Enregistre l'exemplaire dans le cache de son dossier ET dans celui de « Tous ».
    func saveCollectionItemInFolderAndAll(_ item: CollectionItem, username: String) async {
        await saveCollectionItems([item], username: username, folderId: item.folderId)
        await saveCollectionItems([item], username: username, folderId: DiscogsConstants.allFolderId)
    }

    /// Exemplaire changé de dossier (ou remis dans le sien) : retiré du cache de l'ancien dossier,
    /// enregistré dans le nouveau et dans « Tous », et signalé aux autres écrans.
    func replaceCollectionItemInCache(_ old: CollectionItem, with new: CollectionItem, username: String) async {
        removeCollectionItem(username: username, folderId: old.folderId, instanceId: old.instanceId)
        await saveCollectionItemInFolderAndAll(new, username: username)
        LibraryMembershipStore.shared.notifyCollectionInstanceReplaced(oldInstanceId: old.instanceId, newInstance: new)
    }

    /// Retire l'exemplaire du cache de son dossier ET de celui de « Tous ».
    func removeCollectionItemFromFolderAndAll(_ item: CollectionItem, username: String) {
        removeCollectionItem(username: username, folderId: item.folderId, instanceId: item.instanceId)
        removeCollectionItem(username: username, folderId: DiscogsConstants.allFolderId, instanceId: item.instanceId)
    }
}
