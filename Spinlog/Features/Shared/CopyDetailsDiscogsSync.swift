import Foundation

/// Envoi en bloc des prix et états gardés dans l'app vers les champs Discogs associés (« Envoyer
/// tout vers Discogs »). Ce fichier ne contient que le calcul de ce qui reste à envoyer ; l'envoi
/// lui-même est piloté par `CopyDetailsDiscogsSyncViewModel`.
enum CopyDetailsDiscogsSync {
    struct Operation: Equatable {
        let instanceId: Int
        let fieldId: Int
        let value: String
    }

    struct Plan: Equatable {
        /// Valeurs à écrire : champ vide sur Discogs, ou valeur lisible différente de celle de l'app.
        var operations: [Operation] = []
        /// Valeurs déjà identiques sur Discogs.
        var upToDate = 0
        /// Champ Discogs rempli avec une valeur que l'app ne sait pas lire : laissé tel quel, pour ne
        /// pas écraser une information qu'on ne comprend pas.
        var skippedUnreadable = 0
    }

    /// Compare chaque valeur de l'app à celle que Discogs affiche dans `items`. Une valeur absente de
    /// l'app n'est jamais envoyée (rien n'est effacé sur Discogs).
    static func plan(
        items: [CollectionItem],
        details: (Int) -> CopyDetails?,
        priceFieldId: Int?,
        conditionFieldId: Int?,
        defaultCurrency: String
    ) -> Plan {
        var plan = Plan()
        for item in items where item.instanceId > 0 && item.instanceId != item.releaseId {
            guard let local = details(item.instanceId) else { continue }

            if let fieldId = priceFieldId, let price = local.purchasePrice {
                let raw = item.notes.first(where: { $0.fieldId == fieldId })?.value ?? ""
                let blank = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if blank {
                    plan.operations.append(Operation(
                        instanceId: item.instanceId, fieldId: fieldId,
                        value: PurchasePriceParser.canonicalString(amount: price.amount, currency: price.currency)
                    ))
                } else if let remote = PurchasePriceParser.parse(raw, defaultCurrency: defaultCurrency) {
                    if remote.amount == price.amount && remote.currency == price.currency {
                        plan.upToDate += 1
                    } else {
                        plan.operations.append(Operation(
                            instanceId: item.instanceId, fieldId: fieldId,
                            value: PurchasePriceParser.canonicalString(amount: price.amount, currency: price.currency)
                        ))
                    }
                } else {
                    plan.skippedUnreadable += 1
                }
            }

            if let fieldId = conditionFieldId, let grade = local.mediaCondition {
                let raw = item.notes.first(where: { $0.fieldId == fieldId })?.value ?? ""
                let blank = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if blank {
                    plan.operations.append(Operation(instanceId: item.instanceId, fieldId: fieldId, value: grade.discogsLabel))
                } else if let remote = RecordGrade(discogsValue: raw) {
                    if remote == grade {
                        plan.upToDate += 1
                    } else {
                        plan.operations.append(Operation(instanceId: item.instanceId, fieldId: fieldId, value: grade.discogsLabel))
                    }
                } else {
                    plan.skippedUnreadable += 1
                }
            }
        }
        return plan
    }
}
