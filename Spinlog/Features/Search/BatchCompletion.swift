import Foundation

/// Disques qu'un scan par lot vient d'ajouter à la collection et dont l'utilisateur peut
/// renseigner tout de suite le prix d'achat et l'état du média (voir `BatchCompletionSheet`).
/// Présenté avec `sheet(item:)` : l'identifiant change à chaque lot.
struct BatchCompletionRequest: Identifiable {
    let id = UUID()
    let items: [CollectionItem]
    let username: String
}

/// Règles et écriture de la saisie rapide après un scan par lot.
enum BatchCompletion {
    /// Champs proposés pour ce compte : seulement ceux choisis dans Réglages > Prix d'achat et état.
    @MainActor
    static func configuredFields(for username: String) -> [LibraryMissingField] {
        LibraryMissingField.allCases.filter { $0.fieldId(for: username) != nil }
    }

    /// Valeur canonique `"<montant> <devise>"` attendue par Discogs, `nil` si la saisie est vide ou
    /// illisible (virgule ou point décimal acceptés, montant négatif refusé).
    static func canonicalPrice(amountText: String, currency: String) -> String? {
        let normalized = amountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let amount = Double(normalized), amount >= 0 else { return nil }
        return PurchasePriceParser.canonicalString(amount: amount, currency: currency)
    }

    /// Champs à écrire pour cet exemplaire : seulement ceux configurés ET remplis.
    static func values(
        priceFieldId: Int?, mediaConditionFieldId: Int?,
        amountText: String, currency: String, condition: String
    ) -> [(fieldId: Int, value: String)] {
        var result: [(fieldId: Int, value: String)] = []
        if let priceFieldId, let price = canonicalPrice(amountText: amountText, currency: currency) {
            result.append((priceFieldId, price))
        }
        let trimmedCondition = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mediaConditionFieldId, !trimmedCondition.isEmpty {
            result.append((mediaConditionFieldId, trimmedCondition))
        }
        return result
    }

    enum SaveResult {
        case saved
        /// Au moins un champ refusé par Discogs : les autres sont gardés.
        case refused
        /// Le compte actif n'est plus celui du lot : rien n'est écrit.
        case accountChanged
    }

    /// Écrit les champs sur Discogs (file hors ligne comprise, voir `DiscogsWriteService.updateField`),
    /// puis répercute ceux qui ont réussi dans le cache local et la Collection affichée.
    @MainActor
    static func save(_ values: [(fieldId: Int, value: String)], on item: CollectionItem, username: String) async -> SaveResult {
        guard !values.isEmpty else { return .saved }
        guard DiscogsAuthManager.shared.username == username else { return .accountChanged }

        var updated = item
        var anyRefused = false
        for entry in values {
            let outcome = await DiscogsWriteService.updateField(entry.fieldId, value: entry.value, of: item, username: username)
            if outcome == .refused {
                anyRefused = true
            } else {
                updated.notes = updated.notes.settingValue(entry.value, forFieldId: entry.fieldId)
            }
        }
        // Après chaque attente réseau, le compte a pu changer : on n'écrit pas dans un autre cache.
        guard DiscogsAuthManager.shared.username == username else { return .accountChanged }
        if updated.notes.count != item.notes.count || updated.notes.map(\.value) != item.notes.map(\.value) {
            await LocalDataStore.shared.saveCollectionItemInFolderAndAll(updated, username: username)
            LibraryMembershipStore.shared.notifyCollectionInstanceReplaced(oldInstanceId: item.instanceId, newInstance: updated)
        }
        return anyRefused ? .refused : .saved
    }
}
