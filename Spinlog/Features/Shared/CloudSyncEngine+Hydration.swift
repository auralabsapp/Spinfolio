import Foundation
import CloudKit
import OSLog

/// Lance du travail asynchrone sur l'acteur principal SANS hériter du contexte de la tâche
/// appelante. `CKSyncEngine` interdit d'appeler `fetchChanges()` / `sendChanges()` depuis ses
/// propres rappels (`handleEvent`) : une `Task` ordinaire y hérite de ce contexte et fait arrêter
/// l'app (« cannot guarantee serial delegate callbacks if you recurse »).
@discardableResult
func detachedOnMainActor(_ operation: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
    Task.detached(operation: operation)
}

extension CloudSyncEngine {
    // MARK: - Rapatriement (première synchro / changement de compte actif)

    /// Déclenche une récupération complète des changements côté iCloud. Découvre au passage les
    /// zones que cet appareil n'a jamais vues (ex: compte déjà utilisé sur un autre appareil) —
    /// les enregistrements reçus sont filtrés à la zone active dans `apply(remoteRecord:)`.
    func hydrateActiveZone() {
        // `setActiveUsername` est appelé à chaque connexion Discogs, indépendamment du statut
        // premium (voir `DiscogsAuthManager`). Sans ce garde-fou sur `syncEngine`, un utilisateur
        // connecté AVANT de devenir premium déclencherait ici un cycle complet no-op (aucun appel
        // réseau, `markDirty` ignoré partout) qui marquerait quand même `pushDoneKey` à `true` plus
        // bas — et la vraie poussée initiale de ses données pré-existantes ne se déclencherait
        // alors plus jamais lors de son passage effectif au premium.
        guard let activeUsername, syncEngine != nil else {
            cloudSyncLogger.log("hydrateActiveZone() ignoré — activeUsername=\(self.activeUsername ?? "nil", privacy: .private(mask: .hash)) syncEngine=\(self.syncEngine == nil ? "nil" : "ok", privacy: .public)")
            return
        }
        cloudSyncLogger.log("hydrateActiveZone() pour \(activeUsername, privacy: .private(mask: .hash))")

        let pushDoneKey = Self.initialPushDoneKeyPrefix + activeUsername
        guard !UserDefaults.standard.bool(forKey: pushDoneKey) else {
            // Poussée initiale déjà faite pour ce compte sur cet appareil : un simple
            // rafraîchissement suffit, comme à chaque retour au premier plan. On relance aussi
            // l'envoi des changements de ce compte restés en attente pendant qu'un autre compte
            // était actif (voir `nextRecordZoneChangeBatch`).
            fetchLatestChanges()
            scheduleSend()
            return
        }

        // Poussée initiale : les données déjà créées localement avant que la synchro ne soit
        // active n'ont jamais déclenché de `markDirty` — on les envoie donc explicitement pour
        // TOUS les genres synchronisés, mais UNE SEULE FOIS par compte sur cet appareil. Si un
        // genre est ajouté plus tard, voir `resetInitialSyncForActiveAccount()` (option
        // développeur) pour redéclencher manuellement cette poussée sur un appareil qui l'a déjà
        // faite, plutôt que de multiplier les drapeaux de version.
        //
        // Cas critique : un compte utilisé sans premium sur deux appareils, chacun avec ses
        // propres tags/personnalisations de tri/sessions divergents, qui active la synchro sur
        // les deux. Il FAUT récupérer et fusionner (`await performFetchChanges()`, avec
        // `allowMerge` actif pour ce tout premier fetch) ce que l'autre appareil a peut-être déjà
        // poussé AVANT de construire et d'envoyer la poussée initiale de cet appareil — sinon les
        // deux poussées partiraient chacune avec un état purement local, et celle qui arrive en
        // second écraserait celle de l'autre au lieu de fusionner (le `nextRecordZoneChangeBatch`
        // n'envoie jamais que l'état local tel quel, volontairement, pour ne pas ressusciter des
        // suppressions — voir plus bas). Une fois cette fusion faite EN LOCAL, la poussée qui
        // suit envoie déjà l'état fusionné, quel que soit l'ordre d'activation entre les deux
        // appareils.
        // Détachée (voir `detachedOnMainActor`) : `hydrateActiveZone` est appelé depuis
        // `handleEvent` (événement `accountChange`, émis dès le premier démarrage du moteur, donc
        // juste après l'achat Premium).
        let capturedEngine = syncEngine
        detachedOnMainActor { [self] in
            // Sans fusion préalable réussie, pousser l'état local écraserait celui d'un autre
            // appareil (voir ci-dessus) ; et un moteur arrêté ou un autre compte devenu actif
            // pendant l'attente ne doivent ni recevoir cette poussée ni la marquer comme faite.
            // Elle sera retentée au prochain `hydrateActiveZone` (lancement, connexion, Premium).
            let didFetch = await performFetchChanges()
            guard didFetch, capturedEngine === self.syncEngine, self.activeUsername == activeUsername else {
                cloudSyncLogger.log("Poussée initiale reportée — fetch=\(didFetch, privacy: .public)")
                return
            }

            let existingInstanceIds = TagStore.shared.allTaggedInstanceIds()
            let existingSessionIds = ListeningLogStore.shared.allSessionIds()
            let existingDayStamps = LocalDataStore.shared.collectionSnapshotDayStamps(username: activeUsername)
            let existingAlertReleaseIds = WantlistAlertStore.shared.allAlertReleaseIds()
            cloudSyncLogger.log("Poussée initiale de \(existingInstanceIds.count) exemplaire(s) tagué(s), \(existingSessionIds.count) session(s) d'écoute, \(existingDayStamps.count) point(s) d'historique de valeur et \(existingAlertReleaseIds.count) alerte(s) wantlist, ainsi que des préférences")
            // Cède périodiquement la main (toutes les 25 itérations) : pour une grosse collection,
            // ces boucles peuvent enregistrer des centaines/milliers de changements. Sans ces
            // points de cession, tout s'exécute en une seule rafale synchrone sur l'acteur
            // principal, sans jamais laisser SwiftUI rendre une image entre deux — perceptible
            // comme un blocage au moment même de la poussée initiale.
            for (index, instanceId) in existingInstanceIds.enumerated() {
                markTagsDirty(instanceId: instanceId)
                if index % 25 == 24 {
                    await Task.yield()
                    guard self.activeUsername == activeUsername else { return }
                }
            }
            for (index, sessionId) in existingSessionIds.enumerated() {
                markSessionDirty(id: sessionId)
                if index % 25 == 24 {
                    await Task.yield()
                    guard self.activeUsername == activeUsername else { return }
                }
            }
            // Synchro iCloud de l'historique de valeur désactivée tant que le graphique « Évolution de la cote »
            // est masqué : ces points sont des données Discogs conservées au-delà de 6 h (CGU de l'API), à ne
            // réactiver qu'avec l'accord de Discogs. Les points déjà enregistrés en local sont conservés.
            // for dayStamp in existingDayStamps {
            //     markCollectionSnapshotDirty(dayStamp: dayStamp)
            // }
            for (index, releaseId) in existingAlertReleaseIds.enumerated() {
                markWantlistAlertDirty(releaseId: releaseId)
                if index % 25 == 24 {
                    await Task.yield()
                    guard self.activeUsername == activeUsername else { return }
                }
            }
            markCollectionPreferencesDirty()
            markShelfPreferencesDirty()
            markStandaloneTagsDirty()
            markDiscogsWorkCategoriesDirty()
            markAppPreferencesDirty()
            markGradesDirty()
            // Marqué tout de suite, sans attendre la confirmation réseau : les changements sont
            // déjà enregistrés dans l'état persisté du moteur (`state.add` dans `markDirty`), qui
            // les redélivrera lui-même même si cet envoi immédiat échoue (ex: throttling).
            // Attendre le succès avant de marquer redéclencherait la même rafale à chaque
            // lancement tant que l'erreur passagère persiste.
            UserDefaults.standard.set(true, forKey: pushDoneKey)
        }
    }

    /// Option développeur (voir `DeveloperOptionsView`) : oublie que la poussée initiale a déjà
    /// été faite pour le compte actif sur cet appareil, et la redéclenche immédiatement. Utile
    /// pour retester la réconciliation de deux appareils divergents, ou pour repousser
    /// manuellement des données pré-existantes après l'ajout d'un nouveau genre synchronisé.
    func resetInitialSyncForActiveAccount() {
        guard let activeUsername else {
            cloudSyncLogger.log("resetInitialSyncForActiveAccount() ignoré — activeUsername=nil")
            return
        }
        UserDefaults.standard.removeObject(forKey: Self.initialPushDoneKeyPrefix + activeUsername)
        UserDefaults.standard.removeObject(forKey: Self.hydratedFlagKeyPrefix + activeUsername)
        cloudSyncLogger.log("resetInitialSyncForActiveAccount() — drapeaux réinitialisés pour \(activeUsername, privacy: .private(mask: .hash)), nouvelle poussée initiale")
        hydrateActiveZone()
    }

    /// Récupère les derniers changements côté iCloud, sans attendre la fin (fire-and-forget) —
    /// adapté aux déclencheurs premier plan (`hydrateActiveZone`, retour au premier plan), où
    /// personne n'a besoin d'attendre le résultat.
    func fetchLatestChanges() {
        // Détachée pour la même raison que dans `hydrateActiveZone`.
        detachedOnMainActor { [self] in
            await performFetchChanges()
        }
    }

    /// Appelé par `AppDelegate` à la réception d'une notification silencieuse CloudKit, pour que
    /// la récupération se fasse pendant la fenêtre d'exécution en arrière-plan accordée par l'OS.
    /// Contrairement à `fetchLatestChanges()`, celui-ci attend réellement la fin de l'opération :
    /// si on rendait la main avant que `fetchChanges()` ait fini, l'OS pourrait suspendre l'app
    /// avant que la modification distante n'ait été récupérée.
    @discardableResult
    func handleRemoteNotification() async -> Bool {
        cloudSyncLogger.log("handleRemoteNotification() — réveil par notification silencieuse CloudKit")
        return await performFetchChanges()
    }

    /// Cœur partagé de la récupération, utilisé à la fois en fire-and-forget
    /// (`fetchLatestChanges`) et en `await` direct (`handleRemoteNotification`).
    @discardableResult
    private func performFetchChanges() async -> Bool {
        guard let syncEngine, let activeUsername else {
            cloudSyncLogger.log("performFetchChanges() ignoré — syncEngine=\(self.syncEngine == nil ? "nil" : "ok", privacy: .public) activeUsername=\(self.activeUsername ?? "nil", privacy: .private(mask: .hash))")
            return false
        }

        // Seul le tout premier `fetchChanges()` réussi pour ce compte sur cet appareil doit
        // fusionner (union) l'état distant avec le local — voir `apply(remoteRecord:allowMerge:)`
        // pour le détail par genre d'enregistrement. Une fois cette réconciliation faite, tout
        // changement distant reçu doit être appliqué tel quel, sinon une suppression faite sur un
        // autre appareil serait systématiquement "ressuscitée" par l'union avec l'état local.
        let hydratedKey = Self.hydratedFlagKeyPrefix + activeUsername
        let isFirstHydrate = !UserDefaults.standard.bool(forKey: hydratedKey)
        cloudSyncLogger.log("performFetchChanges() — première synchro pour ce compte sur cet appareil : \(isFirstHydrate)")

        do {
            try await syncEngine.fetchChanges()
            cloudSyncLogger.log("fetchChanges() terminé pour \(activeUsername, privacy: .private(mask: .hash))")
            // Moteur remplacé ou compte changé pendant l'attente : ce fetch ne vaut pas
            // réconciliation pour le compte actif.
            guard syncEngine === self.syncEngine, activeUsername == self.activeUsername else { return false }
            if isFirstHydrate {
                UserDefaults.standard.set(true, forKey: hydratedKey)
            }
            return true
        } catch {
            cloudSyncLogger.error("fetchChanges() a échoué pour \(activeUsername, privacy: .private(mask: .hash)) : \(error, privacy: .private)")
            return false
        }
    }

    /// Applique un enregistrement reçu d'iCloud, quel que soit son genre.
    /// - `allowMerge: true` fusionne (union) avec l'état local — réservé à la réconciliation
    ///   initiale de deux appareils divergents (voir `isFirstHydrateForActiveAccount`). Uniquement
    ///   pertinent pour les genres qui représentent une collection pouvant légitimement diverger
    ///   (tags, personnalisations de tri) ; les sessions d'écoute et préférences n'ont pas besoin
    ///   de fusion (identifiées individuellement ou simples scalaires).
    /// - `allowMerge: false` (cas normal, `fetchedRecordZoneChanges`) remplace directement l'état
    ///   local par le contenu distant : c'est ce qui permet à une suppression faite sur un autre
    ///   appareil de se propager correctement, plutôt que d'être ré-ajoutée par une union.
    func apply(remoteRecord record: CKRecord, allowMerge: Bool) {
        guard let activeUsername else {
            cloudSyncLogger.log("apply(remoteRecord:) ignoré — aucun compte actif")
            return
        }
        guard record.recordID.zoneID == zoneID(for: activeUsername) else {
            cloudSyncLogger.log("apply(remoteRecord:) ignoré — zone \(record.recordID.zoneID.zoneName, privacy: .private(mask: .hash)) différente de la zone active")
            return
        }
        guard let kind = SyncedRecordKind.from(recordName: record.recordID.recordName) else {
            cloudSyncLogger.log("apply(remoteRecord:) ignoré — recordName inattendu \(record.recordID.recordName, privacy: .private(mask: .hash))")
            return
        }
        guard let payload = record[Self.payloadField] as? Data else {
            cloudSyncLogger.error("apply(remoteRecord:) — payload absent pour \(String(describing: kind), privacy: .private(mask: .hash))")
            return
        }

        switch kind {
        case .tag(let instanceId):
            guard let remoteTags = try? JSONDecoder().decode([SyncedTag].self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour instance \(instanceId)")
                return
            }
            let resolved: [SyncedTag]
            if allowMerge {
                resolved = TagMergeLogic.merge(local: TagStore.shared.syncSnapshot(for: instanceId), remote: remoteTags)
            } else {
                resolved = remoteTags
            }
            cloudSyncLogger.log("apply(remoteRecord:) tag instance \(instanceId) — remote=\(remoteTags.count) allowMerge=\(allowMerge) résultat=\(resolved.count)")
            TagStore.shared.applyRemoteTags(instanceId: instanceId, tags: resolved)

        case .listeningSession:
            guard let session = try? JSONDecoder().decode(ListeningSession.self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour une session d'écoute")
                return
            }
            cloudSyncLogger.log("apply(remoteRecord:) session d'écoute \(session.id, privacy: .private(mask: .hash))")
            ListeningLogStore.shared.applyRemoteSession(session)

        case .collectionPreferences:
            guard let prefs = try? JSONDecoder().decode(SyncedCollectionPreferences.self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour les préférences de collection")
                return
            }
            cloudSyncLogger.log("apply(remoteRecord:) préférences de collection")
            CollectionPreferencesStore.applyRemotePreferences(
                currency: prefs.defaultCurrency,
                purchasePriceFieldId: prefs.purchasePriceFieldId,
                mediaConditionFieldId: prefs.mediaConditionFieldId,
                defaultAddFolderId: prefs.defaultAddFolderId,
                for: activeUsername
            )

        case .shelfPreferences:
            guard let remotePrefs = try? JSONDecoder().decode(SyncedShelfPreferences.self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour les préférences de rangement")
                return
            }
            let resolvedOverrides: [String: String]
            if allowMerge {
                // Union : ajoute les personnalisations locales absentes du serveur (l'appareil qui
                // n'avait encore rien poussé ne perd pas les siennes). En cas de conflit sur un
                // même artiste (rare), le serveur fait autorité — c'est-à-dire la valeur du
                // PREMIER appareil à avoir synchronisé ce compte, puisque cette fusion tourne
                // toujours après un fetch qui récupère l'état déjà poussé par un appareil
                // précédent (voir `hydrateActiveZone`). Un appareil qui synchronise après un autre
                // hérite donc de ses personnalisations en cas de désaccord, plutôt que d'imposer
                // les siennes.
                resolvedOverrides = remotePrefs.customArtistSortOverrides.merging(ShelfPreferencesStore.shared.customArtistSortOverrides) { remote, _ in remote }
            } else {
                resolvedOverrides = remotePrefs.customArtistSortOverrides
            }
            // La règle de tri, "ignorer les articles" et "trier par nom de famille" sont de
            // simples scalaires (comme `CollectionPreferences`) : pas de fusion possible, le
            // serveur fait toujours autorité — voir `hydrateActiveZone` pour l'explication du
            // choix "premier appareil synchronisé = maître" que ça implique en cas de désaccord.
            let resolvedStrategy = ShelfSortStrategy(rawValue: remotePrefs.sortStrategy) ?? ShelfPreferencesStore.shared.sortStrategy
            cloudSyncLogger.log("apply(remoteRecord:) préférences de rangement — overrides distants=\(remotePrefs.customArtistSortOverrides.count) allowMerge=\(allowMerge) résultat=\(resolvedOverrides.count)")
            ShelfPreferencesStore.shared.applyRemoteShelfPreferences(
                sortStrategy: resolvedStrategy,
                ignoreArticles: remotePrefs.ignoreArticles,
                sortByLastName: remotePrefs.sortByLastName,
                restrictToSameFolder: remotePrefs.restrictToSameFolder,
                customArtistSortOverrides: resolvedOverrides
            )

        case .collectionSnapshot:
            // Synchro iCloud de l'historique de valeur désactivée tant que le graphique « Évolution de la cote »
            // est masqué : ces points sont des données Discogs conservées au-delà de 6 h (CGU de l'API), à ne
            // réactiver qu'avec l'accord de Discogs. Les points déjà enregistrés en local sont conservés.
            // Les points reçus d'un autre appareil sont donc ignorés.
            // guard let snapshot = try? JSONDecoder().decode(SyncedCollectionSnapshot.self, from: payload) else {
            //     cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour un point d'historique de valeur")
            //     return
            // }
            // cloudSyncLogger.log("apply(remoteRecord:) point d'historique de valeur \(dayStamp, privacy: .public)")
            // LocalDataStore.shared.applyRemoteCollectionSnapshot(
            //     username: activeUsername,
            //     date: snapshot.date,
            //     currency: snapshot.currency,
            //     low: snapshot.low,
            //     median: snapshot.median,
            //     high: snapshot.high
            // )
            break

        case .wantlistAlert:
            guard let alert = try? JSONDecoder().decode(WantlistAlert.self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour une alerte wantlist")
                return
            }
            cloudSyncLogger.log("apply(remoteRecord:) alerte wantlist \(alert.releaseId)")
            WantlistAlertStore.shared.applyRemoteAlert(alert)

        case .standaloneTags:
            guard let remoteStandaloneTags = try? JSONDecoder().decode(Set<String>.self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour les tags autonomes")
                return
            }
            // Union pure et sans conflit possible (un ensemble de chaînes, contrairement aux
            // personnalisations de tri qui associent une valeur par artiste) : pas besoin de
            // départager quoi que ce soit, contrairement à `.shelfPreferences`.
            let resolved = allowMerge ? remoteStandaloneTags.union(TagStore.shared.standaloneTags) : remoteStandaloneTags
            cloudSyncLogger.log("apply(remoteRecord:) tags autonomes — remote=\(remoteStandaloneTags.count) allowMerge=\(allowMerge) résultat=\(resolved.count)")
            TagStore.shared.applyRemoteStandaloneTags(resolved)

        case .discogsWorkCategories:
            guard let remoteCategories = try? JSONDecoder().decode([String: String].self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour les sections Discogs")
                return
            }
            // Toujours fusionné, quel que soit `allowMerge` : un classement est une propriété
            // publique du master, identique sur tous les appareils — rien à départager ni à
            // supprimer, contrairement aux données de l'utilisateur.
            cloudSyncLogger.log("apply(remoteRecord:) sections Discogs — remote=\(remoteCategories.count)")
            DiscogsWorkCategoryCache.shared.applyRemote(remoteCategories)

        case .appPreferences:
            guard let prefs = try? JSONDecoder().decode(SyncedAppPreferences.self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour les préférences d'apparence")
                return
            }
            // Scalaires, comme `.collectionPreferences` : pas de fusion possible, le serveur fait
            // toujours autorité.
            cloudSyncLogger.log("apply(remoteRecord:) préférences d'apparence")
            ThemeManager.shared.applyRemoteTheme(AppColorTheme(rawValue: prefs.colorTheme) ?? ThemeManager.shared.currentTheme)
            AppearancePreferencesStore.shared.applyRemotePreferences(
                appearance: AppTheme(rawValue: prefs.appearance) ?? AppearancePreferencesStore.shared.appearance,
                maxListeningDuration: prefs.maxListeningDuration
            )

        case .grades:
            guard let remoteGrades = try? JSONDecoder().decode(SyncedGrades.self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour les grades")
                return
            }
            // Toujours fusionné, quel que soit `allowMerge` : un grade acquis ne se perd pas, la date
            // la plus ancienne l'emporte (voir `GradeRules.merge`).
            cloudSyncLogger.log("apply(remoteRecord:) grades — remote=\(remoteGrades.unlocks.count)")
            GradeStore.shared.applyRemote(remoteGrades)
        }
    }

    /// Applique une suppression reçue d'iCloud. Seules les sessions d'écoute et les alertes
    /// wantlist sont supprimées en tant que `CKRecord` (les tags et préférences ne sont eux
    /// jamais supprimés, uniquement remplacés par un contenu vide/par défaut) — tout autre genre
    /// est ignoré silencieusement.
    func applyDeletion(recordID: CKRecord.ID) {
        guard let activeUsername, recordID.zoneID == zoneID(for: activeUsername) else { return }
        switch SyncedRecordKind.from(recordName: recordID.recordName) {
        case .listeningSession(let id):
            cloudSyncLogger.log("applyDeletion(recordID:) session d'écoute \(id, privacy: .private(mask: .hash))")
            ListeningLogStore.shared.applyRemoteSessionDeletion(id: id)

        case .wantlistAlert(let releaseId):
            cloudSyncLogger.log("applyDeletion(recordID:) alerte wantlist \(releaseId)")
            WantlistAlertStore.shared.applyRemoteAlertDeletion(releaseId: releaseId)

        default:
            break
        }
    }

    /// Construit le contenu (payload JSON) à envoyer pour un genre d'enregistrement donné, à
    /// partir de l'état local actuel — jamais fusionné avec le contenu serveur (voir
    /// `nextRecordZoneChangeBatch`).
    func payloadData(for kind: SyncedRecordKind) -> Data? {
        switch kind {
        case .tag(let instanceId):
            return try? JSONEncoder().encode(TagStore.shared.syncSnapshot(for: instanceId))

        case .listeningSession(let id):
            guard let session = ListeningLogStore.shared.session(id: id) else { return nil }
            return try? JSONEncoder().encode(session)

        case .collectionPreferences:
            guard let activeUsername else { return nil }
            let prefs = SyncedCollectionPreferences(
                defaultCurrency: CollectionPreferencesStore.defaultCurrency(for: activeUsername),
                purchasePriceFieldId: CollectionPreferencesStore.purchasePriceFieldId(for: activeUsername),
                mediaConditionFieldId: CollectionPreferencesStore.mediaConditionFieldId(for: activeUsername),
                defaultAddFolderId: CollectionPreferencesStore.defaultAddFolderId(for: activeUsername)
            )
            return try? JSONEncoder().encode(prefs)

        case .shelfPreferences:
            let prefs = SyncedShelfPreferences(
                sortStrategy: ShelfPreferencesStore.shared.sortStrategy.rawValue,
                ignoreArticles: ShelfPreferencesStore.shared.ignoreArticles,
                sortByLastName: ShelfPreferencesStore.shared.sortByLastName,
                restrictToSameFolder: ShelfPreferencesStore.shared.restrictToSameFolder,
                customArtistSortOverrides: ShelfPreferencesStore.shared.customArtistSortOverrides
            )
            return try? JSONEncoder().encode(prefs)

        case .collectionSnapshot(let dayStamp):
            guard let activeUsername,
                  let snapshot = LocalDataStore.shared.collectionSnapshot(dayStamp: dayStamp, username: activeUsername) else { return nil }
            let synced = SyncedCollectionSnapshot(
                date: snapshot.date,
                currency: snapshot.currency,
                low: snapshot.low,
                median: snapshot.median,
                high: snapshot.high
            )
            return try? JSONEncoder().encode(synced)

        case .wantlistAlert(let releaseId):
            guard let alert = WantlistAlertStore.shared.alert(for: releaseId) else { return nil }
            return try? JSONEncoder().encode(alert)

        case .standaloneTags:
            return try? JSONEncoder().encode(TagStore.shared.standaloneTags)

        case .discogsWorkCategories:
            return try? JSONEncoder().encode(DiscogsWorkCategoryCache.shared.syncPayload)

        case .appPreferences:
            let prefs = SyncedAppPreferences(
                colorTheme: ThemeManager.shared.chosenTheme.rawValue,
                appearance: AppearancePreferencesStore.shared.appearance.rawValue,
                maxListeningDuration: AppearancePreferencesStore.shared.maxListeningDuration
            )
            return try? JSONEncoder().encode(prefs)

        case .grades:
            return try? JSONEncoder().encode(GradeStore.shared.syncPayload)
        }
    }
}
