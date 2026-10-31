import Foundation

/// Écriture du prix d'achat et de l'état du disque : toujours dans l'app d'abord (instantané,
/// sans réseau), puis sur Discogs seulement si les Réglages associent un champ à cette donnée.
/// Le circuit d'envoi est celui des autres champs (`DiscogsWriteService.updateField` : file hors
/// ligne, reprise après erreur passagère).
@MainActor
enum CopyDetailsWriter {
    /// Résultat de l'envoi vers Discogs, `nil` si rien n'a été envoyé (aucun champ associé, démo,
    /// valeur vidée, ou compte qui n'est plus actif).
    @discardableResult
    static func setPurchasePrice(
        _ price: (amount: Double, currency: String)?,
        for item: CollectionItem,
        username: String,
        store: CopyDetailsStore = .shared
    ) async -> DiscogsWriteOutcome? {
        guard store.activeUsername == CopyDetailsStore.normalize(username) else { return nil }
        store.setPurchasePrice(price, for: item.instanceId)
        // Une valeur vidée n'est pas effacée sur Discogs (comme avant).
        guard let price, let fieldId = store.mappedPriceFieldId, !DemoMode.isActive else { return nil }
        let value = PurchasePriceParser.canonicalString(amount: price.amount, currency: price.currency)
        return await DiscogsWriteService.updateField(fieldId, value: value, of: item, username: username)
    }

    @discardableResult
    static func setMediaCondition(
        _ grade: RecordGrade?,
        for item: CollectionItem,
        username: String,
        store: CopyDetailsStore = .shared
    ) async -> DiscogsWriteOutcome? {
        guard store.activeUsername == CopyDetailsStore.normalize(username) else { return nil }
        store.setMediaCondition(grade, for: item.instanceId)
        guard let grade, let fieldId = store.mappedConditionFieldId, !DemoMode.isActive else { return nil }
        return await DiscogsWriteService.updateField(fieldId, value: grade.discogsLabel, of: item, username: username)
    }
}
