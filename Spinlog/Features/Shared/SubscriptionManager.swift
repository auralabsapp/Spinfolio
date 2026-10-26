import Foundation
import StoreKit
import Observation
import OSLog

private nonisolated let logger = Logger(subsystem: AppInfo.logSubsystem, category: "SubscriptionManager")

enum SubscriptionPlanID: String, CaseIterable, Sendable {
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
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var isLoading: Bool = false
    private(set) var isPurchasing: Bool = false
    private(set) var errorMessage: String? = nil

    private var transactionListenerTask: Task<Void, Never>? = nil

    // MARK: - Diagnostic (environnements de test uniquement, voir `SubscriptionDiagnosticSection`)

    /// Droit renvoyé par StoreKit lors de la dernière vérification, retenu ou non.
    struct EntitlementSnapshot: Identifiable, Sendable {
        let id: UInt64
        let productID: String
        let expirationDate: Date?
        let revocationDate: Date?
        let counted: Bool
    }

    /// `true` hors App Store (TestFlight, compte sandbox, fichier StoreKit de Xcode).
    private(set) var isTestEnvironment = false

    /// Diagnostic déverrouillé sur cet appareil (7 touchers sur la version, dans « À propos »).
    /// Masqué par défaut : la revue App Store tourne elle aussi en sandbox, comme TestFlight, et
    /// un examinateur ne doit pas tomber sur cette section de test.
    private(set) var isDiagnosticUnlocked = UserDefaults.standard.bool(forKey: SubscriptionDiagnosticUnlock.defaultsKey)

    /// Le diagnostic d'abonnement est-il affiché dans les Réglages ?
    var showsDiagnostic: Bool { isTestEnvironment && isDiagnosticUnlocked }

    /// Affiche ou masque le diagnostic ; sans effet en production (App Store).
    /// - Returns: `true` si l'état a changé.
    @discardableResult
    func toggleDiagnosticUnlock() -> Bool {
        guard isTestEnvironment else { return false }
        isDiagnosticUnlocked.toggle()
        UserDefaults.standard.set(isDiagnosticUnlocked, forKey: SubscriptionDiagnosticUnlock.defaultsKey)
        return true
    }
    private(set) var lastEntitlementCheck: Date?
    private(set) var lastEntitlements: [EntitlementSnapshot] = []

    private init() {
        startTransactionListener()
    }

    /// Démarre la surveillance continue des transactions StoreKit 2 et synchronise le statut initial
    func start() {
        Task {
            if case .verified(let appTransaction)? = try? await AppTransaction.shared {
                isTestEnvironment = appTransaction.environment != .production
            }
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

    func loadProducts() async {
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

    func purchase(_ plan: SubscriptionPlanID) async throws -> Bool {
        if let product = product(for: plan) {
            return try await purchase(product)
        }

        // Cas où le produit StoreKit n'est pas encore retourné par Apple
        logger.warning("Produit non trouvé auprès de StoreKit pour \(plan.rawValue, privacy: .public).")
        #if DEBUG
        // En mode développement, on simule l'achat pour permettre de tester l'application sans blocage
        try? await Task.sleep(nanoseconds: 500_000_000)
        PremiumStore.shared.developerOverride = true
        return true
        #else
        throw NSError(
            domain: "com.auralabs.Spinlog",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: String(localized: "Le forfait sélectionné n'est pas encore disponible sur l'App Store.")]
        )
        #endif
    }

    func purchase(_ product: Product) async throws -> Bool {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try Self.verify(verification)
            await transaction.finish()
            await updateCustomerProductStatus()
            PremiumStore.shared.hasSubscription = true
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

    func restorePurchases() async throws {
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

    func updateCustomerProductStatus() async {
        var activeIDs: Set<String> = []
        // Seuls les abonnements Premium comptent : un futur achat in-app d'un autre type (ex:
        // pourboire, pack de thèmes) ne doit pas débloquer le Premium par simple présence.
        let premiumProductIDs = Set(SubscriptionPlanID.allCases.map(\.rawValue))

        var snapshots: [EntitlementSnapshot] = []
        let now = Date()

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try Self.verify(result)
                // Expiration revérifiée en plus de la révocation : un droit expiré renvoyé par un
                // cache StoreKit pas encore rafraîchi ne doit pas laisser le Premium actif.
                let isActive = transaction.revocationDate == nil
                    && (transaction.expirationDate.map { $0 > now } ?? true)
                    && premiumProductIDs.contains(transaction.productID)
                if isActive {
                    activeIDs.insert(transaction.productID)
                }
                snapshots.append(EntitlementSnapshot(
                    id: transaction.id,
                    productID: transaction.productID,
                    expirationDate: transaction.expirationDate,
                    revocationDate: transaction.revocationDate,
                    counted: isActive
                ))
            } catch {
                logger.error("Droit actif invalide ou révoqué: \(error.localizedDescription, privacy: .public)")
            }
        }

        purchasedProductIDs = activeIDs
        lastEntitlements = snapshots
        lastEntitlementCheck = now
        let hasActivePremium = !activeIDs.isEmpty

        // Reflète l'état réel des droits StoreKit : true si un abonnement est actif, false sinon
        // (expiration, annulation, remboursement...). Sans le `false`, un utilisateur resterait
        // premium indéfiniment après la fin de son abonnement. Le forçage développeur (Debug) est
        // stocké à part (`PremiumStore.developerOverride`) et n'est donc plus écrasé ici.
        PremiumStore.shared.hasSubscription = hasActivePremium
        logger.info("Droits actifs mis à jour: \(activeIDs.count, privacy: .public) abonnement(s) actif(s)")
    }

    // MARK: - Helpers & Formatage des prix

    func product(for plan: SubscriptionPlanID) -> Product? {
        products.first { $0.id == plan.rawValue }
    }

    var yearlyProduct: Product? {
        product(for: .yearly)
    }

    var monthlyProduct: Product? {
        product(for: .monthly)
    }

    /// Texte d'essai gratuit pour ce forfait (ex. « 7 jours d'essai gratuit »), lu dynamiquement
    /// depuis l'offre introductive StoreKit — `nil` si ce forfait n'a pas d'essai configuré.
    /// Affiché dans le paywall pour respecter la ligne directrice App Review 3.1.2 (conditions
    /// d'essai visibles avant achat).
    func freeTrialText(for plan: SubscriptionPlanID) -> String? {
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

    var yearlyPriceString: String {
        if let product = yearlyProduct {
            return String(localized: "\(product.displayPrice) / an")
        }
        return String(localized: "24,99 € / an")
    }

    var monthlyPriceString: String {
        if let product = monthlyProduct {
            return String(localized: "\(product.displayPrice) / mois")
        }
        return String(localized: "2,99 € / mois")
    }

    /// Prix mensuel le plus bas proposé (équivalent mensuel de l'annuel), formaté dans la devise
    /// de la boutique de l'utilisateur ; `nil` tant que les produits StoreKit ne sont pas chargés.
    /// Remplace un « À partir de 2,50 € / mois » codé en dur, faux hors zone euro et à chaque
    /// changement de tarif.
    var lowestMonthlyPriceString: String? {
        let candidates = [yearlyProduct.map { ($0.price / 12, $0.priceFormatStyle) },
                          monthlyProduct.map { ($0.price, $0.priceFormatStyle) }]
            .compactMap { $0 }
        guard let lowest = candidates.min(by: { $0.0 < $1.0 }) else { return nil }
        return lowest.0.formatted(lowest.1)
    }

    nonisolated static func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
