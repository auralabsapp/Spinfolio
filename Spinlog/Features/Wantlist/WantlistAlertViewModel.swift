import Foundation

@Observable
@MainActor
final class WantlistAlertViewModel {
    private let alertStore = WantlistAlertStore.shared
    private let authManager = DiscogsAuthManager.shared

    /// Texte brut tel que tapé (chiffres + séparateur décimal uniquement, jamais le symbole
    /// monétaire : `TextField(value:format: .currency(...))` reformate le texte à chaque frappe et
    /// perd la position du curseur dès que le symbole fait partie du texte édité — le 2e chiffre
    /// tapé atterrit alors après le symbole au lieu de s'insérer dans le nombre). Vide tant que
    /// l'utilisateur n'a saisi (ou repris) aucun montant — notamment quand il n'y a pas encore
    /// d'alerte active sur ce disque : voir `setupInitialValues`, qui ne le pré-remplit alors plus
    /// avec une suggestion de cote marketplace.
    var targetPriceString: String = ""
    var currency: String = "EUR"

    var targetPrice: Double? {
        let cleaned = targetPriceString.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    /// Symbole monétaire seul (ex: "€", "$" — pas le nom complet "Euro" que renverrait
    /// `Locale.localizedString(forCurrencyCode:)`), affiché en permanence à côté du champ de
    /// saisie, y compris quand il est vide — jamais à l'intérieur du texte édité (voir
    /// `targetPriceString`).
    var currencySymbol: String {
        Self.currencyFormatter.currencyCode = currency
        return Self.currencyFormatter.currencySymbol ?? currency
    }

    /// Partagé (lu par `body` à chaque rendu) plutôt que recréé à chaque accès (§3).
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter
    }()

    private(set) var isLoading = true
    private(set) var currentStats: MarketplaceStats?
    private(set) var convertedLowestPrice: Double?
    private(set) var suggestions: [(condition: String, price: Double)] = []
    private(set) var isSaving = false

    func existingAlert(for item: WantlistItem) -> WantlistAlert? {
        alertStore.alert(for: item.id)
    }

    func applySuggestion(price: Double) {
        targetPriceString = PurchasePriceParser.editableAmountString(price)
    }

    func setupInitialValues(for item: WantlistItem) {
        if let username = authManager.username {
            currency = CollectionPreferencesStore.defaultCurrency(for: username)
        }

        if let existing = existingAlert(for: item) {
            currency = existing.currency
            targetPriceString = PurchasePriceParser.editableAmountString(existing.targetPrice)
        }
    }

    func loadMarketData(for item: WantlistItem) async {
        isLoading = true
        defer { isLoading = false }

        // 1. Statistiques du marché actuel (Option A)
        do {
            let stats = try await DiscogsAPIClient.shared.marketplaceStats(
                releaseId: item.id,
                currency: currency,
                credentials: authManager.credentials
            )
            self.currentStats = stats

            if let lowest = stats.lowestPrice {
                if lowest.currency.uppercased() == currency.uppercased() {
                    convertedLowestPrice = lowest.value
                } else {
                    convertedLowestPrice = await CurrencyConversionService.shared.convert(
                        lowest.value,
                        from: lowest.currency,
                        to: currency
                    )
                }
            }
        } catch {
            currentStats = nil
        }

        // 2. Estimation de cote récente par état (Option B)
        if let credentials = authManager.credentials {
            if let rawSuggestions = try? await DiscogsAPIClient.shared.priceSuggestions(
                releaseId: item.id,
                credentials: credentials
            ) {
                let knownConditions = MediaCondition.allCases.map(\.rawValue)
                var ordered: [(condition: String, price: Double)] = []

                for cond in knownConditions {
                    if let rawPrice = rawSuggestions[cond] {
                        let converted = await CurrencyConversionService.shared.convert(
                            rawPrice.value,
                            from: rawPrice.currency,
                            to: currency
                        )
                        ordered.append((condition: cond, price: converted))
                    }
                }

                // Autres clés inattendues
                for (cond, rawPrice) in rawSuggestions where !knownConditions.contains(cond) {
                    let converted = await CurrencyConversionService.shared.convert(
                        rawPrice.value,
                        from: rawPrice.currency,
                        to: currency
                    )
                    ordered.append((condition: cond, price: converted))
                }

                self.suggestions = ordered
            }
        }
    }

    /// Tente d'enregistrer l'alerte. Renvoie `true` si l'enregistrement a été effectué (la vue
    /// peut alors se fermer), `false` si la permission de notification a été refusée — la vue
    /// doit alors proposer à l'utilisateur de continuer quand même via `saveAlertDirectly`.
    func saveAlert(for item: WantlistItem) async -> Bool {
        guard let price = targetPrice, price > 0 else { return false }

        isSaving = true
        defer { isSaving = false }

        let isAuthorized = await alertStore.hasNotificationAuthorization()
        if !isAuthorized {
            let granted = await alertStore.requestNotificationPermission()
            if !granted {
                return false
            }
        }

        saveAlertDirectly(for: item)
        return true
    }

    func saveAlertDirectly(for item: WantlistItem) {
        guard let price = targetPrice, price > 0 else { return }

        let alert = WantlistAlert(
            releaseId: item.id,
            albumTitle: item.basicInformation.title,
            artistName: item.basicInformation.artistNames,
            coverURL: item.basicInformation.thumb ?? item.basicInformation.coverImage,
            targetPrice: price,
            currency: currency,
            createdAt: existingAlert(for: item)?.createdAt ?? Date(),
            lastCheckedAt: Date(),
            lastNotifiedPrice: existingAlert(for: item)?.lastNotifiedPrice,
            currentLowestPrice: convertedLowestPrice,
            currentLowestPriceCurrency: currency,
            currentNumForSale: currentStats?.numForSale
        )

        alertStore.saveAlert(alert)
    }

    func deleteAlert(for item: WantlistItem) {
        alertStore.removeAlert(for: item.id)
    }
}
