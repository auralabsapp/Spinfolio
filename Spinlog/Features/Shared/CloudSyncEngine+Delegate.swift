import Foundation
import CloudKit
import OSLog

// MARK: - CKSyncEngineDelegate

// La conformité elle-même est déclarée sur la classe (`CloudSyncEngine.swift`) : le protocole
// hérite de `Sendable`, qui doit être adopté dans le fichier où la classe est définie.
extension CloudSyncEngine {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        // Un moteur remplacé (changement de compte iCloud) ou arrêté (fin du premium) peut encore
        // émettre des événements : les traiter réécrirait par exemple son état périmé par-dessus
        // celui du nouveau moteur.
        guard syncEngine === self.syncEngine else {
            cloudSyncLogger.log("handleEvent ignoré — moteur qui n'est plus actif")
            return
        }
        cloudSyncLogger.log("handleEvent: \(String(describing: event), privacy: .public)")
        switch event {
        case .stateUpdate(let stateUpdate):
            if let data = try? JSONEncoder().encode(stateUpdate.stateSerialization) {
                UserDefaults.standard.set(data, forKey: Self.stateStorageKey)
            }

        case .accountChange(let accountChange):
            cloudSyncLogger.log("accountChange: \(String(describing: accountChange), privacy: .public)")
            switch accountChange.changeType {
            case .signIn:
                // Compte iCloud (nouvellement) disponible pour ce moteur : la zone de ce compte
                // iCloud n'a encore jamais reçu les données locales, on refait donc la
                // réconciliation initiale (récupération + fusion, puis poussée complète). Le
                // moteur, lui, est conservé : ce n'est pas un changement de base.
                forgetSyncProgressForAllAccounts()
                hydrateActiveZone()
            case .signOut, .switchAccounts:
                // L'état persisté du moteur (jetons de changement, changements en attente)
                // appartient à l'ancien compte iCloud : le réutiliser avec un autre compte le
                // corromprait. On repart d'un moteur neuf. Les données locales sont conservées
                // (ce sont les données de l'utilisateur, pas un simple cache).
                resetForNewICloudAccount()
            @unknown default:
                resetForNewICloudAccount()
            }

        case .fetchedRecordZoneChanges(let fetchedChanges):
            cloudSyncLogger.log("fetchedRecordZoneChanges — \(fetchedChanges.modifications.count) modification(s), \(fetchedChanges.deletions.count) suppression(s)")
            // Voir le commentaire sur `isApplyingRemoteChange` : couvre toute cette réapplication,
            // pour que `markDirty`/`markDeleted` refusent bruyamment d'être appelées entre-temps.
            isApplyingRemoteChange = true
            defer { isApplyingRemoteChange = false }
            // Un lot peut contenir des centaines d'enregistrements (première synchro) : regroupés
            // pour que chaque store n'écrive sur disque et ne notifie l'UI qu'une fois par lot.
            TagStore.shared.performBatchUpdate {
                ListeningLogStore.shared.performBatchUpdate {
                    for modification in fetchedChanges.modifications {
                        rememberSystemFields(of: modification.record)
                        guard shouldApplyRemote(modification.record) else {
                            cloudSyncLogger.log("fetchedRecordZoneChanges — \(modification.record.recordID.recordName, privacy: .public) ignoré : modification locale plus récente en attente d'envoi")
                            continue
                        }
                        apply(remoteRecord: modification.record, allowMerge: isFirstHydrateForActiveAccount)
                    }
                    for deletion in fetchedChanges.deletions {
                        serverSystemFields[deletion.recordID] = nil
                        applyDeletion(recordID: deletion.recordID)
                    }
                }
            }

        case .sentRecordZoneChanges(let sentChanges):
            cloudSyncLogger.log("sentRecordZoneChanges — \(sentChanges.savedRecords.count) sauvé(s), \(sentChanges.deletedRecordIDs.count) supprimé(s), \(sentChanges.failedRecordSaves.count) échec(s) de sauvegarde, \(sentChanges.failedRecordDeletes.count) échec(s) de suppression")
            for savedRecord in sentChanges.savedRecords {
                rememberSystemFields(of: savedRecord)
                if let activeUsername {
                    CloudSyncModificationLog.clear(
                        savedRecord.recordID.recordName,
                        onlyIfDatedAt: savedRecord[CloudSyncModificationLog.modifiedAtField] as? Date,
                        username: activeUsername
                    )
                }
            }
            for recordID in sentChanges.deletedRecordIDs {
                serverSystemFields[recordID] = nil
            }
            if !sentChanges.failedRecordSaves.isEmpty || !sentChanges.failedRecordDeletes.isEmpty {
                hadRecordLevelFailureInLastSend = true
            }
            for failedSave in sentChanges.failedRecordSaves {
                handleFailedSave(recordID: failedSave.record.recordID, error: failedSave.error, syncEngine: syncEngine)
            }
            for (recordID, error) in sentChanges.failedRecordDeletes {
                handleFailedDelete(recordID: recordID, error: error, syncEngine: syncEngine)
            }

        default:
            break
        }
    }

    /// Remet en attente un enregistrement dont l'envoi a échoué, mais uniquement si un nouvel
    /// essai a une chance d'aboutir. Auparavant, tout échec était remis en attente sans
    /// distinction — y compris les erreurs définitives (quota iCloud plein, permission refusée,
    /// argument invalide…), retentées toutes les 5 secondes indéfiniment.
    private func handleFailedSave(recordID: CKRecord.ID, error: CKError, syncEngine: CKSyncEngine) {
        cloudSyncLogger.error("failedRecordSave \(recordID.recordName, privacy: .public) : \(String(describing: error), privacy: .public)")
        switch error.code {
        case .serverRecordChanged:
            // Le serveur a une autre version. La plus récente des deux l'emporte (voir
            // `CloudSyncModificationLog`) : si c'est celle du serveur, on l'applique localement et
            // on renonce à l'envoi ; sinon on renvoie le contenu local, à partir des métadonnées
            // de la version serveur (voir `nextRecordZoneChangeBatch`).
            if let serverRecord = error.serverRecord {
                rememberSystemFields(of: serverRecord)
                if shouldApplyRemote(serverRecord) {
                    isApplyingRemoteChange = true
                    apply(remoteRecord: serverRecord, allowMerge: false)
                    isApplyingRemoteChange = false
                    cloudSyncLogger.log("serverRecordChanged \(recordID.recordName, privacy: .public) : version serveur plus récente appliquée")
                    return
                }
            }
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

        case .zoneNotFound:
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: recordID.zoneID))])
            serverSystemFields[recordID] = nil
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

        case .unknownItem:
            // Supprimé côté serveur entre-temps : les métadonnées mémorisées ne sont plus
            // valides, le prochain envoi le recrée.
            serverSystemFields[recordID] = nil
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

        case .networkFailure, .networkUnavailable, .serviceUnavailable, .zoneBusy,
             .requestRateLimited, .notAuthenticated, .accountTemporarilyUnavailable,
             .operationCancelled, .batchRequestFailed:
            // Passager : nouvel essai (avec le délai de `scheduleSend`).
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

        default:
            // Définitif (ex: `.quotaExceeded`, `.permissionFailure`, `.invalidArguments`, ou
            // `.userDeletedZone` — l'utilisateur a lui-même effacé les données iCloud de l'app,
            // à respecter). Abandonné : la prochaine modification locale de cet enregistrement
            // le renverra de toute façon.
            cloudSyncLogger.error("failedRecordSave \(recordID.recordName, privacy: .public) abandonné (erreur définitive \(error.code.rawValue, privacy: .public))")
        }
    }

    private func handleFailedDelete(recordID: CKRecord.ID, error: CKError, syncEngine: CKSyncEngine) {
        cloudSyncLogger.error("failedRecordDelete \(recordID.recordName, privacy: .public) : \(String(describing: error), privacy: .public)")
        switch error.code {
        case .unknownItem, .zoneNotFound, .userDeletedZone:
            // Déjà absent du serveur : le but de la suppression est atteint.
            serverSystemFields[recordID] = nil

        case .networkFailure, .networkUnavailable, .serviceUnavailable, .zoneBusy,
             .requestRateLimited, .notAuthenticated, .accountTemporarilyUnavailable,
             .operationCancelled, .batchRequestFailed:
            syncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])

        default:
            cloudSyncLogger.error("failedRecordDelete \(recordID.recordName, privacy: .public) abandonné (erreur définitive \(error.code.rawValue, privacy: .public))")
        }
    }

    private func rememberSystemFields(of record: CKRecord) {
        serverSystemFields[record.recordID] = Self.encodedSystemFields(of: record)
    }

    private nonisolated static func encodedSystemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private nonisolated static func record(fromSystemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    /// Nombre de disques traités par lot. À l'origine fixé à 1 (voir commentaire historique
    /// ci-dessous pour le raisonnement) : observé comme beaucoup trop lent pour une poussée
    /// initiale un peu conséquente (~150 disques ⇒ plus d'une minute, chaque disque attendant son
    /// propre aller-retour réseau de récupération de la version serveur avant d'être sauvé, l'un
    /// après l'autre). Toujours largement sous la limite d'opération CloudKit (400 disques), donc
    /// encore raisonnablement isolant : un conflit dans un lot de `batchSize` ne fait échouer que
    /// ce lot, pas l'ensemble de la poussée ni les lots suivants.
    private static let batchSize = 25

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard syncEngine === self.syncEngine else { return nil }
        // Plusieurs disques par lot plutôt qu'un seul (voir `batchSize`) : CloudKit envoie
        // toujours chaque lot comme une opération réseau atomique par zone, donc un conflit sur
        // l'un des disques du lot peut encore faire échouer les autres disques DU MÊME LOT (déjà
        // observé par le passé avec un lot "tout en un seul bloc") — mais CKSyncEngine rappelle
        // cette méthode autant de fois que nécessaire tant qu'un lot non-nil est renvoyé, donc les
        // lots suivants restent traités indépendamment les uns des autres.
        // Uniquement les changements de la zone du compte actif : les payloads sont reconstruits
        // ci-dessous depuis les stores locaux, qui ne contiennent que les données du compte actif
        // (vidés après déconnexion). Envoyer un changement resté en attente pour la zone d'un autre
        // compte y écrirait donc des données vides ou celles du mauvais compte — écrasant par
        // exemple sur iCloud les tags du compte précédent, puis sur tous ses autres appareils.
        // Ces changements restent en attente et partiront, avec les bonnes données, quand leur
        // compte redeviendra actif.
        let changes = Array(pendingChangesForActiveZone(syncEngine)
            .filter { context.options.scope.contains($0) }
            .prefix(Self.batchSize))
        guard !changes.isEmpty else { return nil }

        // Précalculé en synchrone, pour tous les disques du lot d'un coup : seule la récupération
        // de la version serveur ci-dessous a réellement besoin d'être refaite par disque.
        // Capturé en `let` (immuable) par le closure ci-dessous, qui tourne hors de l'acteur
        // principal (`@Sendable`) : une capture par référence mutable (`var`) y serait interdite.
        let username = activeUsername
        let payloadsByRecordID: [CKRecord.ID: (kind: SyncedRecordKind, payload: Data, modifiedAt: Date)] = changes.reduce(into: [:]) { result, change in
            guard case .saveRecord(let recordID) = change else { return }
            guard let kind = SyncedRecordKind.from(recordName: recordID.recordName),
                  let payload = payloadData(for: kind) else { return }
            let modifiedAt = username.flatMap { CloudSyncModificationLog.pendingDate(for: recordID.recordName, username: $0) } ?? Date()
            result[recordID] = (kind, payload, modifiedAt)
        }

        // `.deleteRecord` : CKSyncEngine gère la suppression sans consulter `recordProvider` — il
        // suffit de lui transmettre le changement tel quel au sein du même lot.
        // Métadonnées système (identité/version) de la dernière version serveur connue, capturées
        // en `Data` (Sendable) pour le closure ci-dessous.
        let systemFieldsByRecordID = serverSystemFields.filter { payloadsByRecordID[$0.key] != nil }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            guard let (kind, payload, modifiedAt) = payloadsByRecordID[recordID] else { return nil }

            // Repart de la dernière version serveur connue (voir `serverSystemFields`), mais
            // UNIQUEMENT pour ses métadonnées système — jamais pour fusionner son contenu.
            // Fusionner (union) le contenu serveur avec l'état local ici referait exactement le
            // bug déjà corrigé côté réception : si l'utilisateur vient de retirer un tag
            // localement, le serveur a encore l'ancienne liste (le retrait n'a pas encore été
            // poussé) — une union des deux ferait "ressusciter" le tag qu'on vient de retirer. Le
            // contenu envoyé est donc toujours l'état local actuel tel quel.
            //
            // Plus de `database.record(for:)` réseau par disque (25 allers-retours par lot) : si
            // ces métadonnées sont absentes ou périmées, CloudKit refuse la sauvegarde avec
            // `.serverRecordChanged` en renvoyant la version serveur, que `handleEvent` mémorise
            // avant de remettre le changement en attente — d'où au pire un aller-retour de plus.
            let record = systemFieldsByRecordID[recordID].flatMap(Self.record(fromSystemFields:))
                ?? CKRecord(recordType: kind.recordType, recordID: recordID)
            record[Self.payloadField] = payload as CKRecordValue
            record[CloudSyncModificationLog.modifiedAtField] = modifiedAt as CKRecordValue
            return record
        }
    }

    /// Applique-t-on cette version distante, ou garde-t-on une modification locale plus récente
    /// encore en attente d'envoi ? Voir `CloudSyncModificationLog.remoteWins`. Une version
    /// distante appliquée remplace la modification locale, qui n'est donc plus en attente.
    func shouldApplyRemote(_ record: CKRecord) -> Bool {
        guard let activeUsername,
              let kind = SyncedRecordKind.from(recordName: record.recordID.recordName),
              !kind.isAlwaysMerged else { return true }
        let recordName = record.recordID.recordName
        let wins = CloudSyncModificationLog.remoteWins(
            remoteModifiedAt: record[CloudSyncModificationLog.modifiedAtField] as? Date,
            localPendingAt: CloudSyncModificationLog.pendingDate(for: recordName, username: activeUsername)
        )
        if wins {
            CloudSyncModificationLog.clear(recordName, username: activeUsername)
        }
        return wins
    }
}
