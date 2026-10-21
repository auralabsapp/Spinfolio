import Foundation
import OSLog

private let storeDecodingLogger = Logger(subsystem: "com.auralabs.Spinlog", category: "PersistedStoreDecoding")

/// Chargement tolérant des stores persistés en JSON dans `UserDefaults` (tags, écoutes, alertes,
/// file hors ligne).
///
/// Avant cet utilitaire, un seul élément illisible (champ ajouté puis retiré entre deux versions,
/// écriture interrompue…) faisait échouer tout le décodage : le store repartait à vide, et sa
/// prochaine écriture effaçait définitivement les données sur le disque. Désormais :
/// - les éléments illisibles sont ignorés un par un, les autres sont conservés ;
/// - dès que quelque chose n'a pas pu être lu, les octets d'origine sont copiés sous une clé de
///   secours (`<clé>.unreadableBackup`) avant toute réécriture, pour pouvoir être récupérés.
enum PersistedStoreDecoding {
    static func backupKey(for key: String) -> String { "\(key).unreadableBackup" }

    /// Tableau d'éléments, en ignorant ceux qui ne se décodent pas. `nil` si la clé est absente.
    static func decodeArray<Element: Decodable>(
        _ elementType: Element.Type,
        forKey key: String,
        defaults: UserDefaults = .standard
    ) -> [Element]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let lossy = try? JSONDecoder().decode(LossyArray<Element>.self, from: data) else {
            preserveUnreadable(data, forKey: key, defaults: defaults, reason: "structure illisible")
            return []
        }
        if lossy.droppedCount > 0 {
            preserveUnreadable(data, forKey: key, defaults: defaults, reason: "\(lossy.droppedCount) élément(s) illisible(s)")
        }
        return lossy.elements
    }

    /// Dictionnaire de tableaux (ex. tags par exemplaire), en ignorant les éléments illisibles de
    /// chaque tableau. `nil` si la clé est absente.
    static func decodeDictionaryOfArrays<Element: Decodable>(
        _ elementType: Element.Type,
        forKey key: String,
        defaults: UserDefaults = .standard
    ) -> [String: [Element]]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let lossy = try? JSONDecoder().decode([String: LossyArray<Element>].self, from: data) else {
            preserveUnreadable(data, forKey: key, defaults: defaults, reason: "structure illisible")
            return [:]
        }
        let dropped = lossy.values.reduce(0) { $0 + $1.droppedCount }
        if dropped > 0 {
            preserveUnreadable(data, forKey: key, defaults: defaults, reason: "\(dropped) élément(s) illisible(s)")
        }
        return lossy.mapValues(\.elements)
    }

    /// Conserve la toute première version illisible rencontrée : une copie déjà présente n'est pas
    /// écrasée, pour ne jamais remplacer les données d'origine par une version déjà appauvrie.
    private static func preserveUnreadable(_ data: Data, forKey key: String, defaults: UserDefaults, reason: String) {
        let backup = backupKey(for: key)
        if defaults.data(forKey: backup) == nil {
            defaults.set(data, forKey: backup)
        }
        storeDecodingLogger.error("Store \(key, privacy: .private(mask: .hash)) partiellement illisible (\(reason, privacy: .public)) : copie de secours conservée.")
    }
}

/// Tableau JSON dont les éléments illisibles sont ignorés au lieu de faire échouer le décodage.
/// `nonisolated` et non privé : réutilisé pour décoder hors du fil principal les pages de
/// collection reçues de Discogs (`CollectionReleasesResponse`).
nonisolated struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]
    let droppedCount: Int

    /// Consomme un élément sans le lire, pour avancer après un élément illisible (quel que soit
    /// son type JSON : objet, chaîne, nombre…).
    private struct Skipped: Decodable {
        nonisolated init(from decoder: Decoder) throws {}
    }

    nonisolated init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        var dropped = 0
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                dropped += 1
                // Sans cette lecture, le conteneur resterait bloqué sur l'élément illisible.
                if (try? container.decode(Skipped.self)) == nil {
                    break
                }
            }
        }
        self.elements = elements
        self.droppedCount = dropped
    }
}
