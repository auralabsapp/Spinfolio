import Foundation
import StoreKit
import Observation
import OSLog

private nonisolated let logger = Logger(subsystem: "com.auralabs.Spinlog", category: "SubscriptionManager")

public enum SubscriptionPlanID: String, CaseIterable, Sendable {
    case yearly = "com.auralabs.Spinlog.premium.yearly"
    case monthly = "com.auralabs.Spinlog.premium.monthly"
}

/// Gestionnaire des abonnements Spinlog Premium basé sur StoreKit 2.
///
/// Gère la récupération des produits auprès de l'App Store, l'exécution des achats
/// sécurisés, la vérification des reçus cryptographiques Apple (JWS), l'écoute des
/// renouvellements en arrière-plan et la synchronisation avec `PremiumStore`.
@Observable
@MainActor
public final class SubscriptionManager {
    public static let shared = SubscriptionManager()

    public private(set) var products: [Product] = []
    public private(set) var purchasedProductIDs: Set<String> = []
    public private(set) var isLoading: Bool = false
    public private(set) var isPurchasing: Bool = false
    public private(set) var errorMessage: String? = nil

    private var transactionListenerTask: Task<Void, Never>? = nil

    private init() {
        startTransactionListener()
    }

    /// Démarre la surveillance continue des transactions StoreKit 2 et synchronise le statut initial
    public func start() {
        Task {
            await loadProducts()
            await updateCustomerProductStatus()
        }
    }

    // MARK: - Écoute des transactions en arrière-plan

    private func startTransactionListener() {
        transactionListenerTask?.cancel()
        transactionListenerTask = Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                do {
                    let transaction = try Self.verify(result)
                    await transaction.finish()
                    await self?.updateCustomerProductStatus()
                } catch {
                    logger.error("Échec de vérification de la transaction: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Chargement des produits

    public func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let productIDs = Set(SubscriptionPlanID.allCases.map(\.rawValue))
            let loadedProducts = try await Product.products(for: productIDs)

            // Ordonne : annuel en premier, mensuel en second
            products = loadedProducts.sorted { p1, p2 in
                if p1.id == SubscriptionPlanID.yearly.rawValue { return true }
                if p2.id == SubscriptionPlanID.yearly.rawValue { return false }
                return p1.id < p2.id
            }
            logger.info("StoreKit 2: \(self.products.count, privacy: .public) produits chargés avec succès")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("StoreKit 2: Impossible de charger les produits: \(error.localizedDescription, privacy: .public)")
        }

        isLoading = false
    }

    // MARK: - Achat

    public func purchase(_ plan: SubscriptionPlanID) async throws -> Bool {
        if let product = product(for: plan) {
            return try await purchase(product)
        }

        // Cas où le produit StoreKit n'est pas encore retourné par Apple
        logger.warning("Produit non trouvé auprès de StoreKit pour \(plan.rawValue, privacy: .public).")
        #if DEBUG
        // En mode développement, on simule l'achat pour permettre de tester l'application sans blocage
        try? await Task.sleep(nanoseconds: 500_000_000)
        PremiumStore.shared.isPremium = true
        return true
        #else
        throw NSError(
            domain: "com.auralabs.Spinlog",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: String(localized: "Le forfait sélectionné n'est pas encore disponible sur l'App Store.")]
        )
        #endif
    }

    public func purchase(_ product: Product) async throws -> Bool {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try Self.verify(verification)
            await transaction.finish()
            await updateCustomerProductStatus()
            PremiumStore.shared.isPremium = true
            return true

        case .userCancelled:
            return false

        case .pending:
            logger.info("Achat en attente d'approbation parentale ou bancaire")
            return false

        @unknown default:
            return false
        }
    }

    // MARK: - Restauration des achats

    public func restorePurchases() async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await updateCustomerProductStatus()
        } catch {
            logger.warning("Restauration StoreKit : \(error.localizedDescription, privacy: .public)")
            #if !DEBUG
            throw error
            #endif
        }
    }

    // MARK: - Vérification des droits actifs

    public func updateCustomerProductStatus() async {
        var activeIDs: Set<String> = []
        // Seuls les abonnements Premium comptent : un futur achat in-app d'un autre type (ex:
        // pourboire, pack de thèmes) ne doit pas débloquer le Premium par simple présence.
        let premiumProductIDs = Set(SubscriptionPlanID.allCases.map(\.rawValue))

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try Self.verify(result)
                if transaction.revocationDate == nil, premiumProductIDs.contains(transaction.productID) {
                    activeIDs.insert(transaction.productID)
                }
            } catch {
                logger.error("Droit actif invalide ou révoqué: \(error.localizedDescription, privacy: .public)")
            }
        }

        purchasedProductIDs = activeIDs
        let hasActivePremium = !activeIDs.isEmpty

        // Reflète l'état réel des droits StoreKit : true si un abonnement est actif, false sinon
        // (expiration, annulation, remboursement...). Sans le `false`, un utilisateur resterait
        // premium indéfiniment après la fin de son abonnement.
        #if DEBUG
        // Préserve le bascule manuel de l'option développeur "Compte Premium" en debug : on ne
        // force jamais à false ici, seulement à true si un vrai abonnement StoreKit est détecté.
        if hasActivePremium {
            PremiumStore.shared.isPremium = true
        }
        #else
        PremiumStore.shared.isPremium = hasActivePremium
        #endif
        logger.info("Droits actifs mis à jour: \(activeIDs.count, privacy: .public) abonnement(s) actif(s)")
    }

    // MARK: - Helpers & Formatage des prix

    public func product(for plan: SubscriptionPlanID) -> Product? {
        products.first { $0.id == plan.rawValue }
    }

    public var yearlyProduct: Product? {
        product(for: .yearly)
    }

    public var monthlyProduct: Product? {
        product(for: .monthly)
    }

    /// Texte d'essai gratuit pour ce forfait (ex. « 7 jours d'essai gratuit »), lu dynamiquement
    /// depuis l'offre introductive StoreKit — `nil` si ce forfait n'a pas d'essai configuré.
    /// Affiché dans le paywall pour respecter la ligne directrice App Review 3.1.2 (conditions
    /// d'essai visibles avant achat).
    public func freeTrialText(for plan: SubscriptionPlanID) -> String? {
        guard let offer = product(for: plan)?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let count = offer.period.value * offer.periodCount
        guard count > 0 else { return nil }
        // Une phrase complète par unité : les variantes singulier/pluriel sont dans le catalogue.
        switch offer.period.unit {
        case .week: return String(localized: "\(count) semaines d'essai gratuit")
        case .month: return String(localized: "\(count) mois d'essai gratuit")
        case .year: return String(localized: "\(count) ans d'essai gratuit")
        default: return String(localized: "\(count) jours d'essai gratuit")
        }
    }

    public var yearlyPriceString: String {
        if let product = yearlyProduct {
            return String(localized: "\(product.displayPrice) / an")
        }
        return String(localized: "24,99 € / an")
    }

    public var monthlyPriceString: String {
        if let product = monthlyProduct {
            return String(localized: "\(product.displayPrice) / mois")
        }
        return String(localized: "2,99 € / mois")
    }

    /// Prix mensuel le plus bas proposé (équivalent mensuel de l'annuel), formaté dans la devise
    /// de la boutique de l'utilisateur ; `nil` tant que les produits StoreKit ne sont pas chargés.
    /// Remplace un « À partir de 2,50 € / mois » codé en dur, faux hors zone euro et à chaque
    /// changement de tarif.
    public var lowestMonthlyPriceString: String? {
        let candidates = [yearlyProduct.map { ($0.price / 12, $0.priceFormatStyle) },
                          monthlyProduct.map { ($0.price, $0.priceFormatStyle) }]
            .compactMap { $0 }
        guard let lowest = candidates.min(by: { $0.0 < $1.0 }) else { return nil }
        return lowest.0.formatted(lowest.1)
    }

    /// Équivalent mensuel de l'abonnement annuel calculé dynamiquement
    public var yearlyMonthlyEquivalentString: String {
        if let yearlyProduct = yearlyProduct {
            let monthlyPriceDecimal = yearlyProduct.price / 12
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = Locale.current
            if let formatted = formatter.string(from: monthlyPriceDecimal as NSDecimalNumber) {
                return String(localized: "(\(formatted)/mois)")
            }
        }
        return String(localized: "(2,08 €/mois)")
    }

    /// Pourcentage d'économie de l'abonnement annuel par rapport à 12 mois payés au tarif mensuel,
    /// calculé dynamiquement pour ne pas se désynchroniser des tarifs réels à chaque changement de
    /// prix (contrairement à un badge "ÉCONOMISEZ X%" codé en dur).
    public var yearlySavingsPercentString: String {
        if let yearlyProduct, let monthlyProduct, monthlyProduct.price > 0 {
            let fullYearAtMonthlyRate = monthlyProduct.price * 12
            let savings = 1 - (yearlyProduct.price / fullYearAtMonthlyRate)
            let percent = Int(((savings as NSDecimalNumber).doubleValue * 100).rounded())
            if percent > 0 {
                return String(localized: "ÉCONOMISE \(percent) %")
            }
        }
        return String(localized: "ÉCONOMISE \(30) %")
    }

    public nonisolated static func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
