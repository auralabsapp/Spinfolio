import Foundation

/// Disques qu'un scan par lot vient d'ajouter à la collection et dont l'utilisateur peut
/// renseigner tout de suite le prix d'achat et l'état du média (voir `BatchCompletionSheet`).
/// Présenté avec `sheet(item:)` : l'identifiant change à chaque lot.
struct BatchCompletionRequest: Identifiable {
    let id = UUID()
    let items: [CollectionItem]
    let username: String
}

/// Règles et écriture de la saisie rapide après un ajout (scan par lot ou fiche d'un album).
enum BatchCompletion {
    /// La saisie rapide est proposée après un ajout : réglage du compte, activé par défaut.
    @MainActor
    static func isOffered(for username: String) -> Bool {
        CollectionPreferencesStore.offersCompletionAfterAdd(for: username)
    }

    /// Prix lu dans une saisie : virgule ou point décimal acceptés, montant négatif ou illisible
    /// refusé, `nil` si la saisie est vide.
    static func parsedPrice(amountText: String, currency: String) -> (amount: Double, currency: String)? {
        let normalized = amountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let amount = Double(normalized), amount >= 0 else { return nil }
        return (amount, currency)
    }

    /// Valeur canonique `"<montant> <devise>"` attendue par Discogs, `nil` si la saisie est vide ou
    /// illisible.
    static func canonicalPrice(amountText: String, currency: String) -> String? {
        parsedPrice(amountText: amountText, currency: currency).map {
            PurchasePriceParser.canonicalString(amount: $0.amount, currency: $0.currency)
        }
    }

    enum SaveResult {
        case saved
        /// Discogs a refusé l'envoi : la valeur reste enregistrée dans l'app.
        case refused
        /// Le compte actif n'est plus celui du lot : rien n'est écrit.
        case accountChanged
    }

    /// Enregistre prix et état de l'exemplaire (dans l'app, puis sur Discogs si un champ y est
    /// associé dans Réglages). Un champ laissé vide n'est pas touché.
    @MainActor
    static func save(
        price: (amount: Double, currency: String)?,
        condition: RecordGrade?,
        on item: CollectionItem,
        username: String
    ) async -> SaveResult {
        guard price != nil || condition != nil else { return .saved }
        guard DiscogsAuthManager.shared.username == username else { return .accountChanged }

        var anyRefused = false
        if let price,
           await CopyDetailsWriter.setPurchasePrice(price, for: item, username: username) == .refused {
            anyRefused = true
        }
        if let condition,
           await CopyDetailsWriter.setMediaCondition(condition, for: item, username: username) == .refused {
            anyRefused = true
        }
        // Après chaque attente réseau, le compte a pu changer.
        guard DiscogsAuthManager.shared.username == username else { return .accountChanged }
        return anyRefused ? .refused : .saved
    }
}
