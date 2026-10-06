import Foundation

@Observable
@MainActor
final class WantlistAlertViewModel {
    private let alertStore = WantlistAlertStore.shared
    private let authManager = DiscogsAuthManager.shared

    var targetPriceString: String = ""
    var currency: String = "EUR"

    private(set) var isLoading = true
    private(set) var currentStats: MarketplaceStats?
    private(set) var convertedLowestPrice: Double?
    private(set) var suggestions: [(condition: String, price: Double)] = []
    private(set) var isSaving = false

    func existingAlert(for item: WantlistItem) -> WantlistAlert? {
        alertStore.alert(for: item.id)
    }

    var parsedTargetPrice: Double? {
        let cleaned = targetPriceString.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    var currencySymbol: String {
        Locale.current.localizedString(forCurrencyCode: currency) ?? currency
    }

    func applySuggestion(price: Double) {
        targetPriceString = String(format: "%.2f", price)
    }

    func setupInitialValues(for item: WantlistItem) {
        if let username = authManager.username {
            currency = CollectionPreferencesStore.defaultCurrency(for: username)
        }

        if let existing = existingAlert(for: item) {
            currency = existing.currency
            targetPriceString = String(format: "%.2f", existing.targetPrice)
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

                // Pré-remplit si pas encore de valeur
                if targetPriceString.isEmpty, let converted = convertedLowestPrice {
                    targetPriceString = String(format: "%.2f", converted)
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
        guard let price = parsedTargetPrice, price > 0 else { return false }

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
        guard let price = parsedTargetPrice, price > 0 else { return }

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
