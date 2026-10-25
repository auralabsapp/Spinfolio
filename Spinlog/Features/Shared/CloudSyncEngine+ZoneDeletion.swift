import Foundation
import CloudKit
import OSLog

/// Suppression d'une zone de compte reçue d'iCloud : « Supprimer mes données » fait sur un autre
/// appareil, ou données de l'app effacées dans Réglages iOS > iCloud. Auparavant ignorée : les autres
/// appareils gardaient tout, et leur prochaine modification recréait la zone (les données effacées
/// réapparaissaient).
extension CloudSyncEngine {
    nonisolated enum ZoneDeletionResponse: Equatable {
        /// La suppression vient de l'utilisateur : elle s'applique aussi à cet appareil.
        case clearLocalData
        /// iCloud a perdu les données chiffrées (réinitialisation du trousseau) : rien n'a été
        /// voulu par l'utilisateur, on renvoie tout le contenu local.
        case reuploadLocalData
    }

    nonisolated static func response(to reason: CKDatabase.DatabaseChange.Deletion.Reason) -> ZoneDeletionResponse {
        switch reason {
        case .encryptedDataReset:
            return .reuploadLocalData
        case .deleted, .purged:
            return .clearLocalData
        @unknown default:
            // Raison inconnue : ne rien effacer, renvoyer au pire des données déjà présentes ici.
            return .reuploadLocalData
        }
    }

    /// Compte Discogs d'une zone `account-<username>` (voir `zoneID(for:)`), `nil` pour toute
    /// autre zone.
    nonisolated static func username(fromZoneName zoneName: String) -> String? {
        let prefix = "account-"
        guard zoneName.hasPrefix(prefix) else { return nil }
        let username = String(zoneName.dropFirst(prefix.count))
        return username.isEmpty ? nil : username
    }

    func handleZoneDeletion(
        zoneID: CKRecordZone.ID,
        reason: CKDatabase.DatabaseChange.Deletion.Reason,
        syncEngine: CKSyncEngine
    ) {
        guard let username = Self.username(fromZoneName: zoneID.zoneName) else { return }
        let response = Self.response(to: reason)
        cloudSyncLogger.log("Zone \(zoneID.zoneName, privacy: .private(mask: .hash)) supprimée sur iCloud — \(String(describing: response), privacy: .public)")

        // Métadonnées serveur de cette zone : elles désignent des enregistrements qui n'existent plus.
        serverSystemFields = serverSystemFields.filter { $0.key.zoneID != zoneID }
        // Réconciliation et poussée initiales à refaire : la zone (re)créée repart de ce que
        // l'appareil possède après coup.
        UserDefaults.standard.removeObject(forKey: Self.hydratedFlagKeyPrefix + username)
        UserDefaults.standard.removeObject(forKey: Self.initialPushDoneKeyPrefix + username)

        switch response {
        case .clearLocalData:
            // Changements en attente pour cette zone : envoyés, ils recréeraient la zone avec les
            // données qu'on vient d'effacer.
            let staleRecordChanges = syncEngine.state.pendingRecordZoneChanges.filter { change in
                switch change {
                case .saveRecord(let recordID), .deleteRecord(let recordID):
                    return recordID.zoneID == zoneID
                @unknown default:
                    return false
                }
            }
            syncEngine.state.remove(pendingRecordZoneChanges: staleRecordChanges)
            let staleZoneSaves = syncEngine.state.pendingDatabaseChanges.filter { change in
                if case .saveZone(let zone) = change { return zone.zoneID == zoneID }
                return false
            }
            syncEngine.state.remove(pendingDatabaseChanges: staleZoneSaves)
            CloudSyncModificationLog.clearAll(for: username)

            // Données synchronisées de ce compte seulement (même liste que la zone) : le cache
            // Discogs et les réglages d'appareil (rangement, thème, apparence) ne sont pas touchés.
            // Aucune de ces méthodes ne signale de changement à envoyer.
            TagStore.shared.clearAccountData(for: username)
            ListeningLogStore.shared.clearAccountData(for: username)
            WantlistAlertStore.shared.clearAccountData(for: username)
            GradeStore.shared.clearAccountData(for: username)
            CollectionPreferencesStore.clearAccountData(for: username)

        case .reuploadLocalData:
            if username == activeUsername {
                hydrateActiveZone()
            }
        }
    }
}
