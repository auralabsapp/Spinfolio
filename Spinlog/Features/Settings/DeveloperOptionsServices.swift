import SwiftUI

// Exclu des builds Release/App Store, comme `DeveloperOptionsView` dont il porte la logique.
#if DEBUG

/// Alimentation ponctuelle du champ personnalisé « Prix d'achat net » (outil développeur).
enum NetPurchasePriceBackfill {
    enum Outcome {
        case fieldsUnavailable
        case discountFieldMissing
        case netFieldMissing
        case finished(updated: Int, failures: Int)
    }

    /// Recalcule "Prix d'achat net" (Prix d'achat − Réduction, chaque champ manquant valant 0)
    /// pour tout exemplaire de la collection possédant au moins l'un des deux champs renseigné,
    /// et pousse le résultat sur Discogs. Les champs sont retrouvés par nom (insensible à la
    /// casse/aux accents) plutôt que par un réglage dédié : ce sont deux champs que l'utilisateur
    /// vient de créer sur discogs.com pour cet outil ponctuel.
    static func run(username: String, credentials: DiscogsCredentials) async -> Outcome {
        guard let fieldsResponse = try? await DiscogsAPIClient.shared.collectionFields(username: username, credentials: credentials) else {
            return .fieldsUnavailable
        }
        guard let discountField = matchCollectionField(named: "réduc", in: fieldsResponse.fields) else {
            return .discountFieldMissing
        }
        guard let netField = matchCollectionField(named: "prix d'achat net", in: fieldsResponse.fields) else {
            return .netFieldMissing
        }

        let items = await LocalDataStore.shared.getAllCollectionItems(username: username)
        let defaultCurrency = CollectionPreferencesStore.defaultCurrency(for: username)

        var updatedCount = 0
        var failureCount = 0

        for item in items {
            // Prix d'achat : celui gardé dans l'app (voir `CopyDetailsStore`).
            let purchaseRaw = CopyDetailsStore.shared.purchasePrice(for: item.instanceId).map {
                PurchasePriceParser.canonicalString(amount: $0.amount, currency: $0.currency)
            } ?? ""
            let discountRaw = item.value(forFieldId: discountField.id)
            guard !purchaseRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !discountRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let purchase = PurchasePriceParser.parse(purchaseRaw, defaultCurrency: defaultCurrency)
            let discount = PurchasePriceParser.parse(discountRaw, defaultCurrency: defaultCurrency)
            let net = (purchase?.amount ?? 0) - (discount?.amount ?? 0)
            let currency = purchase?.currency ?? discount?.currency ?? defaultCurrency
            let canonical = PurchasePriceParser.canonicalString(amount: net, currency: currency)

            do {
                try await DiscogsAPIClient.shared.updateCollectionField(
                    username: username,
                    folderId: item.folderId,
                    releaseId: item.releaseId,
                    instanceId: item.instanceId,
                    fieldId: netField.id,
                    value: canonical,
                    credentials: credentials
                )
                var updatedItem = item
                if let noteIndex = updatedItem.notes.firstIndex(where: { $0.fieldId == netField.id }) {
                    updatedItem.notes[noteIndex] = CollectionFieldValue(fieldId: netField.id, value: canonical)
                } else {
                    updatedItem.notes.append(CollectionFieldValue(fieldId: netField.id, value: canonical))
                }
                await LocalDataStore.shared.saveCollectionItems([updatedItem], username: username, folderId: item.folderId)
                await LocalDataStore.shared.saveCollectionItems([updatedItem], username: username, folderId: DiscogsConstants.allFolderId)
                updatedCount += 1
            } catch {
                failureCount += 1
            }
        }
        return .finished(updated: updatedCount, failures: failureCount)
    }

    private static func matchCollectionField(named target: String, in fields: [CollectionField]) -> CollectionField? {
        let normalizedTarget = normalizedFieldName(target)
        return fields.first { normalizedFieldName($0.name) == normalizedTarget }
    }

    /// Ne garde que lettres/chiffres (repliés sans accent/casse) : insensible aux apostrophes
    /// (droite ' vs typographique ’) et aux espacements, qui font sinon échouer une comparaison
    /// stricte alors que le champ existe bel et bien sur Discogs.
    private static func normalizedFieldName(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(Character.init)
            .reduce(into: "") { $0.append($1) }
    }
}

#endif
