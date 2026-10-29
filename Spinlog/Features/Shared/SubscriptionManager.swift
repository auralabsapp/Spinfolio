import Foundation
import StoreKit
import Observation
import OSLog

private nonisolated let logger = Logger(subsystem: AppInfo.logSubsystem, category: "SubscriptionManager")

/// Abonnements auto-renouvelables : seuls produits qui ont une offre d'essai, une période et un
/// groupe (`freeTrialText`, `product(for:)`).
nonisolated enum SubscriptionPlanID: String, CaseIterable, Sendable {
    case yearly = "com.auralabs.Spinlog.premium.yearly"
    case monthly = "com.auralabs.Spinlog.premium.monthly"
}

/// Tous les produits qui donnent le Premium. Type à part de `SubscriptionPlanID` : l'achat à vie est
/// un achat intégré non consommable, sans période ni offre d'essai, et l'ajouter à ce `CaseIterable`
/// ferait remonter un « forfait » sans abonnement dans tout ce qui parcourt les abonnements.
nonisolated enum PremiumProductID {
    /// Achat unique, non consommable : « Premium pour toujours ».
    static let lifetime = "com.auralabs.Spinlog.premium.lifetime"
    static let subscriptions = Set(SubscriptionPlanID.allCases.map(\.rawValue))
    /// Abonnements + achat à vie : un produit hors de cet ensemble ne débloque rien.
    static let all = subscriptions.union([lifetime])
}

/// Gestionnaire du Premium Spinlog (abonnements et achat à vie) basé sur StoreKit 2.
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
    private var storefrontListenerTask: Task<Void, Never>? = nil

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
        startStorefrontListener()
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

    /// Un prix StoreKit est une photo prise à un instant : si la boutique change (autre pays, autre compte,
    /// compte de test), les produits déjà chargés gardent l'ancienne devise alors que la feuille d'achat
    /// d'Apple affiche la nouvelle. On les recharge donc à chaque changement de boutique.
    private func startStorefrontListener() {
        storefrontListenerTask?.cancel()
        storefrontListenerTask = Task { [weak self] in
            for await _ in Storefront.updates {
                guard !Task.isCancelled else { return }
                await self?.loadProducts()
            }
        }
    }

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
            let loadedProducts = try await Product.products(for: PremiumProductID.all)

            // Ordonne : annuel, puis mensuel, puis achat à vie. Un produit absent de la réponse
            // (pas encore approuvé, réseau) n'apparaît simplement pas.
            let order = [SubscriptionPlanID.yearly.rawValue, SubscriptionPlanID.monthly.rawValue, PremiumProductID.lifetime]
            products = loadedProducts.sorted { p1, p2 in
                (order.firstIndex(of: p1.id) ?? order.count) < (order.firstIndex(of: p2.id) ?? order.count)
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
            try await completePurchase(verification)
            // `hasSubscription` : nom conservé, il signifie « possède le Premium » (abonnement ou
            // achat à vie), pas seulement un abonnement.
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

    /// Valide une transaction reçue d'un achat, d'un code d'offre ou de la boutique StoreKit : la
    /// vérifie (JWS), la termine puis recalcule les droits. Chemin commun du paywall, de la
    /// saisie d'un code et de `purchase(_:)`.
    /// - Throws: l'erreur de vérification si la transaction n'est pas authentique.
    func completePurchase(_ verification: VerificationResult<Transaction>) async throws {
        let transaction = try Self.verify(verification)
        await transaction.finish()
        await updateCustomerProductStatus()
    }

    /// Issue d'une saisie de code d'offre (feuille système `offerCodeRedemption`) : le message à
    /// afficher, ou `nil` si la personne a simplement fermé la feuille. La transaction passe par le
    /// même chemin que tout achat (`completePurchase`).
    func handleOfferCodeResult(_ result: Result<VerificationResult<Transaction>, Error>) async -> String? {
        switch result {
        case .success(let verification):
            do {
                try await completePurchase(verification)
                return AppMessages.offerCodeRedeemed
            } catch {
                logger.error("Code d'offre : transaction non vérifiée: \(error.localizedDescription, privacy: .public)")
                return AppMessages.purchaseVerificationFailed
            }
        case .failure(let error):
            if case StoreKitError.userCancelled = error { return nil }
            logger.error("Code d'offre : échec: \(error.localizedDescription, privacy: .public)")
            return AppMessages.offerCodeFailed
        }
    }

    /// Avant iOS 27, la feuille de code d'offre ne renvoie pas la transaction : elle arrive par
    /// `Transaction.updates` (voir `startTransactionListener`, qui la termine). On relit les droits
    /// pour que le Premium soit déjà actif quand le message s'affiche.
    func handleLegacyOfferCodeResult(_ result: Result<Void, Error>) async -> String? {
        switch result {
        case .success:
            await updateCustomerProductStatus()
            return AppMessages.offerCodeRedeemed
        case .failure(let error):
            if case StoreKitError.userCancelled = error { return nil }
            logger.error("Code d'offre : échec: \(error.localizedDescription, privacy: .public)")
            return AppMessages.offerCodeFailed
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
        // Seuls les produits Premium comptent (abonnements et achat à vie) : un futur achat in-app
        // d'un autre type (ex: pourboire, pack de thèmes) ne doit pas débloquer le Premium par
        // simple présence.
        var snapshots: [EntitlementSnapshot] = []
        let now = Date()

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try Self.verify(result)
                let isActive = Self.isEntitlementActive(
                    productID: transaction.productID,
                    expirationDate: transaction.expirationDate,
                    revocationDate: transaction.revocationDate,
                    now: now
                )
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

        // Reflète l'état réel des droits StoreKit : true si un abonnement est actif ou si l'achat à
        // vie est possédé, false sinon (expiration, annulation, remboursement...). Sans le `false`,
        // un utilisateur resterait premium indéfiniment après la fin de son abonnement. Le forçage développeur (Debug) est
        // stocké à part (`PremiumStore.developerOverride`) et n'est donc plus écrasé ici.
        PremiumStore.shared.hasSubscription = hasActivePremium
        logger.info("Droits actifs mis à jour: \(activeIDs.count, privacy: .public) droit(s) Premium actif(s)")
    }

    /// Un droit StoreKit donne-t-il le Premium ? Révocation (remboursement…) et expiration sont
    /// revérifiées : un droit expiré renvoyé par un cache StoreKit pas encore rafraîchi ne doit pas
    /// laisser le Premium actif. L'achat à vie n'a pas de date d'expiration : actif tant qu'il n'est
    /// pas révoqué. Un produit hors `premiumProductIDs` ne débloque rien.
    nonisolated static func isEntitlementActive(
        productID: String,
        expirationDate: Date?,
        revocationDate: Date?,
        now: Date,
        premiumProductIDs: Set<String> = PremiumProductID.all
    ) -> Bool {
        revocationDate == nil
            && (expirationDate.map { $0 > now } ?? true)
            && premiumProductIDs.contains(productID)
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

    /// Achat à vie ; `nil` tant que StoreKit ne le renvoie pas (réseau, produit pas encore approuvé) :
    /// le paywall masque alors l'offre sans erreur.
    var lifetimeProduct: Product? {
        products.first { $0.id == PremiumProductID.lifetime }
    }

    /// Achat à vie possédé (et non révoqué).
    var hasLifetime: Bool {
        purchasedProductIDs.contains(PremiumProductID.lifetime)
    }

    /// Au moins un abonnement actif (essai compris) : à résilier séparément après un achat à vie,
    /// Apple ne le résilie pas.
    var hasActiveSubscription: Bool {
        !purchasedProductIDs.isDisjoint(with: PremiumProductID.subscriptions)
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

    /// Économie en pourcentage de l'annuel par rapport à douze mensualités, arrondie à l'entier ;
    /// `nil` si l'annuel ne coûte pas moins cher (aucune économie à annoncer).
    nonisolated static func yearlySavingsPercent(yearly: Decimal, monthly: Decimal) -> Int? {
        let twelveMonths = monthly * 12
        guard twelveMonths > 0, yearly < twelveMonths else { return nil }
        let ratio = (twelveMonths - yearly) / twelveMonths * 100
        let percent = Int(truncating: NSDecimalNumber(decimal: ratio).rounding(accordingToBehavior: nil))
        return percent > 0 ? percent : nil
    }

    /// Économie de l'annuel face au mensuel, d'après les prix StoreKit chargés.
    var yearlySavingsPercent: Int? {
        guard let yearly = yearlyProduct, let monthly = monthlyProduct else { return nil }
        return Self.yearlySavingsPercent(yearly: yearly.price, monthly: monthly.price)
    }

    /// Équivalent mensuel de l'abonnement annuel (prix annuel ÷ 12), dans la devise de la boutique.
    var yearlyMonthlyEquivalentString: String? {
        guard let yearly = yearlyProduct else { return nil }
        // Réglages de nombres de l'appareil (virgule ou point), pas ceux de la boutique de l'App Store :
        // comme `displayPrice`, qui s'affiche déjà ainsi à côté.
        return (yearly.price / 12).formatted(yearly.priceFormatStyle.locale(.autoupdatingCurrent))
    }

    /// Prix mensuel le plus bas proposé (équivalent mensuel de l'annuel), formaté dans la devise
    /// de la boutique de l'utilisateur ; `nil` tant que les produits StoreKit ne sont pas chargés.
    /// Remplace un prix codé en dur, faux hors zone euro et à chaque changement de tarif.
    var lowestMonthlyPriceString: String? {
        let candidates = [yearlyProduct.map { ($0.price / 12, $0.priceFormatStyle) },
                          monthlyProduct.map { ($0.price, $0.priceFormatStyle) }]
            .compactMap { $0 }
        guard let lowest = candidates.min(by: { $0.0 < $1.0 }) else { return nil }
        // Réglages de nombres de l'appareil, pas ceux de la boutique (voir `yearlyMonthlyEquivalentString`).
        return lowest.0.formatted(lowest.1.locale(.autoupdatingCurrent))
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
