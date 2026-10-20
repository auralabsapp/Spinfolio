import Foundation

/// Mémorise sur l'appareil la section (Albums, Singles & EP…) de chaque master Discogs déjà
/// classé. Classer un master coûte une requête (son pressage principal, voir
/// `ArtistDetailViewModel.classifyDiscogsWorks`), limitée par le débit de l'API Discogs ; or ce
/// classement ne change pas : une fois connu, il est réutilisé pour tous les artistes et à
/// chaque ouverture de page, sans nouvelle requête. Conservé sans limite de durée : c'est une
/// information déduite des formats, pas une copie de données Discogs soumise à la règle des
/// 6 heures. Synchronisé sur iCloud (premium, voir `CloudSyncEngine`) pour qu'un classement
/// fait sur un appareil serve aux autres ; le cache local, lui, n'est pas lié à un compte
/// (c'est une propriété publique du master, pas une donnée de l'utilisateur).
@MainActor
final class DiscogsWorkCategoryCache {
    static let shared = DiscogsWorkCategoryCache()

    private let storageKey = "discogsMasterCategories"
    private var categoriesByMasterId: [Int: DiscogsWorkCategory]
    private var pendingWrites = 0
    /// Classements écrits localement mais pas encore signalés à iCloud (voir `flush`).
    private var hasUnsyncedChanges = false
    private var lastSyncMarkDate: Date?
    /// Un signalement iCloud renvoie tout le dictionnaire : au plus un toutes les 5 minutes
    /// pendant un classement en tâche de fond, plutôt qu'à chaque lot.
    private let minSyncMarkInterval: TimeInterval = 5 * 60

    private init() {
        let stored = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        var decoded: [Int: DiscogsWorkCategory] = [:]
        for (key, value) in stored {
            if let masterId = Int(key), let category = DiscogsWorkCategory(rawValue: value) {
                decoded[masterId] = category
            }
        }
        categoriesByMasterId = decoded
    }

    func category(forMasterId masterId: Int) -> DiscogsWorkCategory? {
        categoriesByMasterId[masterId]
    }

    func store(_ category: DiscogsWorkCategory, forMasterId masterId: Int) {
        guard categoriesByMasterId[masterId] != category else { return }
        categoriesByMasterId[masterId] = category
        // Écriture groupée : tout le dictionnaire (plusieurs milliers d'entrées après un
        // classement en tâche de fond) est réécrit à chaque sauvegarde, inutile de le faire à
        // chaque master classé.
        pendingWrites += 1
        if pendingWrites >= 50 {
            flush()
        }
    }

    /// Écrit les classements en attente (appelé en fin de classement et par lots de 50), et les
    /// signale à iCloud pour les autres appareils (sans effet hors premium : voir
    /// `CloudSyncEngine`) — au plus toutes les 5 minutes, sauf `forceSync` (passage de l'app en
    /// arrière-plan), qui signale aussi ce qui avait été retenu.
    func flush(forceSync: Bool = false) {
        if pendingWrites > 0 {
            pendingWrites = 0
            persist()
            hasUnsyncedChanges = true
        }
        guard hasUnsyncedChanges else { return }
        let now = Date()
        if forceSync || lastSyncMarkDate.map({ now.timeIntervalSince($0) >= minSyncMarkInterval }) ?? true {
            hasUnsyncedChanges = false
            lastSyncMarkDate = now
            CloudSyncEngine.shared.markDiscogsWorkCategoriesDirty()
        }
    }

    /// Représentation synchronisée sur iCloud : identifiant de master → section (valeur brute).
    /// Quelques dizaines d'octets par master : même plusieurs milliers restent très loin de la
    /// limite de taille d'un enregistrement CloudKit (1 Mo).
    var syncPayload: [String: String] {
        Dictionary(uniqueKeysWithValues: categoriesByMasterId.map { (String($0.key), $0.value.rawValue) })
    }

    /// Fusionne les classements reçus d'iCloud. Les classements locaux sont conservés en cas de
    /// divergence : les deux viennent du même pressage principal, ils ne diffèrent que si les
    /// règles de classement ont changé entre deux versions de l'app. Ne re-signale rien à
    /// iCloud (sinon chaque réception relancerait un envoi).
    func applyRemote(_ remote: [String: String]) {
        var added = 0
        for (key, value) in remote {
            guard let masterId = Int(key), let category = DiscogsWorkCategory(rawValue: value),
                  categoriesByMasterId[masterId] == nil else { continue }
            categoriesByMasterId[masterId] = category
            added += 1
        }
        if added > 0 {
            persist()
        }
    }

    /// Efface tous les classements (suppression des données du compte). N'en signale rien à
    /// iCloud : la zone du compte est supprimée séparément (`CloudSyncEngine.deleteCloudData`).
    func clearAll() {
        categoriesByMasterId = [:]
        pendingWrites = 0
        hasUnsyncedChanges = false
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func persist() {
        UserDefaults.standard.set(syncPayload, forKey: storageKey)
    }
}
