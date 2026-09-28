import Foundation

/// Un tag synchronisé via iCloud, avec sa date d'ajout — miroir public du `TimestampedTag` privé
/// de `TagStore`, utilisé comme frontière d'échange avec `CloudSyncEngine`.
struct SyncedTag: Codable, Hashable, Sendable {
    let name: String
    let addedAt: Date
}

/// Fusionne les tags d'un même exemplaire connus localement et ceux connus par iCloud, sans
/// aucune dépendance à CloudKit — logique pure et testable isolément.
///
/// Utilisée à la première synchronisation d'un compte sur un appareil (ou à la réactivation du
/// compte premium) quand deux appareils ont pu diverger avant d'être synchronisés : union des
/// deux listes de tags (par nom, insensible à la casse), puis troncature à
/// `TagConstants.maxTagsPerInstance` en conservant les tags les plus récemment ajoutés si
/// l'union dépasse cette limite.
enum TagMergeLogic {
    static func merge(local: [SyncedTag], remote: [SyncedTag]) -> [SyncedTag] {
        var byLowercasedName: [String: SyncedTag] = [:]
        for tag in local + remote {
            let key = tag.name.lowercased()
            if let existing = byLowercasedName[key] {
                // Un même tag ajouté indépendamment sur les deux appareils garde la date la plus
                // ancienne des deux : c'est la date à laquelle ce tag a réellement été appliqué
                // pour la première fois, et ça évite de le pénaliser à tort à la troncature.
                byLowercasedName[key] = tag.addedAt < existing.addedAt ? tag : existing
            } else {
                byLowercasedName[key] = tag
            }
        }

        let union = byLowercasedName.values.sorted { $0.addedAt < $1.addedAt }
        guard union.count > TagConstants.maxTagsPerInstance else { return union }
        return Array(union.suffix(TagConstants.maxTagsPerInstance))
    }
}
