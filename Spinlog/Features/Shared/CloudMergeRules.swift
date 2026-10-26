import Foundation

/// Règles de fusion des données reçues d'iCloud, sans dépendance à CloudKit ni aux stores :
/// fonctions pures appelées par `CloudSyncEngine.apply(remoteRecord:allowMerge:)` et testées
/// isolément.
///
/// `allowMerge` vaut `true` seulement à la réconciliation initiale de deux appareils divergents
/// (voir `isFirstHydrateForActiveAccount`). Hors de ce cas, le contenu distant remplace l'état
/// local : c'est ce qui propage une suppression faite sur un autre appareil, au lieu de la
/// ré-ajouter par une union.
enum CloudMergeRules {
    /// Tags d'un exemplaire : union par nom (voir `TagMergeLogic`) à la réconciliation initiale,
    /// sinon remplacement (un tableau distant vide efface les tags locaux).
    static func tags(local: [SyncedTag], remote: [SyncedTag], allowMerge: Bool) -> [SyncedTag] {
        allowMerge ? TagMergeLogic.merge(local: local, remote: remote) : remote
    }

    /// Tags autonomes : union pure, sans conflit possible (un ensemble de chaînes).
    static func standaloneTags(local: Set<String>, remote: Set<String>, allowMerge: Bool) -> Set<String> {
        allowMerge ? remote.union(local) : remote
    }

    /// Personnalisations de tri par artiste : union qui garde les entrées locales absentes du
    /// serveur (l'appareil qui n'avait encore rien poussé ne perd pas les siennes). Sur un même
    /// artiste, le serveur fait autorité : c'est la valeur du premier appareil synchronisé,
    /// puisque cette fusion tourne après un fetch de l'état déjà poussé.
    static func shelfOverrides(local: [String: String], remote: [String: String], allowMerge: Bool) -> [String: String] {
        allowMerge ? remote.merging(local) { remote, _ in remote } : remote
    }

    /// Valeur d'un réglage scalaire reçu sous forme de chaîne : repli sur la valeur actuelle si
    /// elle est inconnue (réglage ajouté par une version plus récente de l'app sur un autre
    /// appareil), plutôt que d'abandonner tout l'enregistrement.
    static func setting<Value: RawRepresentable>(rawValue: Value.RawValue, fallback: Value) -> Value {
        Value(rawValue: rawValue) ?? fallback
    }
}
