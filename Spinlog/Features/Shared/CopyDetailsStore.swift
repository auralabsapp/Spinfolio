import Foundation
import Observation

/// Prix d'achat et état du disque de chaque exemplaire (niveau `instanceId`), gardés dans l'app.
/// Contrairement aux champs personnalisés de Discogs, ils n'exigent ni champ à créer sur le site ni
/// connexion : la saisie est locale, Discogs ne reçoit ces valeurs que si l'utilisateur le demande.
///
/// Données isolées par compte Discogs (`setActiveUsername`, comme `TagStore`) : vidées de la
/// mémoire à la déconnexion, restaurées à la reconnexion du même compte.
///
/// Les champs Discogs que les Réglages associent au prix et à l'état (`mappedPriceFieldId`,
/// `mappedConditionFieldId`) servent à reprendre les valeurs déjà saisies sur Discogs
/// (`adoptLegacyValues`, une seule fois par exemplaire, sans jamais écraser une saisie locale) et à
/// leur renvoyer les nouvelles (`CopyDetailsWriter`).
@Observable
@MainActor
final class CopyDetailsStore {
    static let shared = CopyDetailsStore()

    private struct StoredEntry: Codable {
        let instanceId: Int
        let details: CopyDetails
    }

    private(set) var entries: [Int: CopyDetails] = [:]
    private(set) var activeUsername: String?

    /// Champs Discogs que les Réglages associent au prix et à l'état, relus à chaque changement de
    /// préférences : pas de lecture de `UserDefaults` à chaque affichage d'une ligne.
    private(set) var mappedPriceFieldId: Int?
    private(set) var mappedConditionFieldId: Int?

    private static let storageKey = "com.spinlog.copyDetails"

    /// Profondeur des `performBatchUpdate` en cours (voir `TagStore.performBatchUpdate`).
    @ObservationIgnored private var batchDepth = 0
    @ObservationIgnored private var needsPersistAfterBatch = false

    private let defaults: UserDefaults

    /// `defaults` injectable pour les tests ; l'instance partagée utilise les réglages standard.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        NotificationCenter.default.addObserver(
            forName: .collectionPreferencesChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMapping() }
        }
    }

    // MARK: - Compte actif

    /// Bascule sur les données du compte indiqué (ou les vide de la mémoire si `nil`). Appelé par
    /// `DiscogsAuthManager`, comme pour les autres stores isolés par compte.
    func setActiveUsername(_ username: String?) {
        let normalized = Self.normalize(username)
        guard normalized != activeUsername else { return }
        activeUsername = normalized
        guard let normalized else {
            entries = [:]
            mappedPriceFieldId = nil
            mappedConditionFieldId = nil
            return
        }
        load(for: normalized)
        refreshMapping()
        adoptFromCache()
    }

    nonisolated static func normalize(_ username: String?) -> String? {
        guard let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func key(for username: String) -> String {
        "\(storageKey)_\(username)"
    }

    private func load(for username: String) {
        let stored = PersistedStoreDecoding.decodeArray(StoredEntry.self, forKey: Self.key(for: username), defaults: defaults) ?? []
        entries = Dictionary(stored.map { ($0.instanceId, $0.details) }, uniquingKeysWith: { first, second in
            first.modifiedAt >= second.modifiedAt ? first : second
        })
    }

    /// Supprime définitivement les données d'un compte (mémoire et disque).
    func clearAccountData(for username: String) {
        guard let normalized = Self.normalize(username) else { return }
        defaults.removeObject(forKey: Self.key(for: normalized))
        if activeUsername == normalized {
            entries = [:]
        }
    }

    // MARK: - Lecture

    func details(for instanceId: Int) -> CopyDetails? {
        entries[instanceId]
    }

    func purchasePrice(for instanceId: Int) -> (amount: Double, currency: String)? {
        entries[instanceId]?.purchasePrice
    }

    func mediaCondition(for instanceId: Int) -> RecordGrade? {
        entries[instanceId]?.mediaCondition
    }

    /// Valeur sous la forme qu'aurait le champ Discogs associé (prix `"25.50 EUR"`, état en toutes
    /// lettres), pour la liste des champs personnalisés de « Mon exemplaire », qui garde ces deux
    /// champs visibles. `nil` si ce n'est pas l'un des deux champs ou si l'exemplaire n'a aucune
    /// entrée locale : l'écran garde alors la valeur Discogs.
    func fieldValue(forFieldId fieldId: Int, instanceId: Int) -> String? {
        guard let entry = entries[instanceId] else { return nil }
        if fieldId == mappedPriceFieldId {
            guard let price = entry.purchasePrice else { return "" }
            return PurchasePriceParser.canonicalString(amount: price.amount, currency: price.currency)
        }
        if fieldId == mappedConditionFieldId {
            return entry.mediaCondition?.discogsLabel ?? ""
        }
        return nil
    }

    /// Vrai si cette valeur de champ Discogs correspond déjà à ce que garde l'app pour ce champ
    /// (même prix et même devise, ou même état), quelle que soit l'écriture (« 25,5 € », « 25.50 EUR »).
    func isFieldValue(_ value: String, equivalentToStoredFor fieldId: Int, instanceId: Int, username: String) -> Bool {
        guard let stored = entries[instanceId] else { return false }
        if fieldId == mappedPriceFieldId {
            guard let parsed = PurchasePriceParser.parse(value, defaultCurrency: CollectionPreferencesStore.defaultCurrency(for: username)) else {
                return stored.purchasePrice == nil && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return stored.purchaseAmount == parsed.amount && stored.purchaseCurrency == parsed.currency
        }
        if fieldId == mappedConditionFieldId {
            return stored.mediaCondition == RecordGrade(discogsValue: value)
        }
        return true
    }

    /// Copie dans le store une valeur écrite sur le champ Discogs associé (modification faite dans
    /// la liste des champs personnalisés). Sans effet pour un autre champ ou un autre compte ; un
    /// état illisible laisse l'état enregistré tel quel.
    func mirrorWrite(fieldId: Int, value: String, instanceId: Int, username: String) {
        guard Self.normalize(username) == activeUsername else { return }
        let blank = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if fieldId == mappedPriceFieldId {
            let defaultCurrency = CollectionPreferencesStore.defaultCurrency(for: username)
            if blank {
                setPurchasePrice(nil, for: instanceId)
            } else if let parsed = PurchasePriceParser.parse(value, defaultCurrency: defaultCurrency) {
                setPurchasePrice(parsed, for: instanceId)
            }
        } else if fieldId == mappedConditionFieldId {
            if blank {
                setMediaCondition(nil, for: instanceId)
            } else if let grade = RecordGrade(discogsValue: value) {
                setMediaCondition(grade, for: instanceId)
            }
        }
    }

    /// Prix d'achat renseignés, additionnés par devise. Les exemplaires sans prix sont ignorés.
    func purchaseAmountsByCurrency(forInstanceIds instanceIds: some Sequence<Int>) -> [String: Double] {
        var amounts: [String: Double] = [:]
        for instanceId in instanceIds {
            guard let price = entries[instanceId]?.purchasePrice else { continue }
            amounts[price.currency, default: 0] += price.amount
        }
        return amounts
    }

    // MARK: - Écriture

    func setPurchasePrice(_ price: (amount: Double, currency: String)?, for instanceId: Int) {
        update(instanceId) { details in
            details.purchaseAmount = price?.amount
            details.purchaseCurrency = price?.currency
        }
    }

    func setMediaCondition(_ grade: RecordGrade?, for instanceId: Int) {
        update(instanceId) { $0.mediaCondition = grade }
    }

    private func update(_ instanceId: Int, _ change: (inout CopyDetails) -> Void) {
        var details = entries[instanceId] ?? CopyDetails()
        let before = details
        change(&details)
        guard details != before else { return }
        details.modifiedAt = .now
        entries[instanceId] = details
        persist()
    }

    // MARK: - Reprise des valeurs Discogs

    /// Crée l'entrée des exemplaires qui n'en ont pas encore, à partir des champs Discogs associés.
    /// Une entrée existante (même vidée par l'utilisateur) n'est jamais modifiée, et un exemplaire
    /// sans valeur lisible n'en reçoit pas : il reste repris si une valeur apparaît plus tard.
    func adoptLegacyValues(from items: [CollectionItem], username: String) {
        guard Self.normalize(username) == activeUsername,
              mappedPriceFieldId != nil || mappedConditionFieldId != nil else { return }
        let defaultCurrency = CollectionPreferencesStore.defaultCurrency(for: username)
        performBatchUpdate {
            for item in items where item.instanceId > 0 && item.instanceId != item.releaseId {
                guard entries[item.instanceId] == nil else { continue }
                var details = CopyDetails(modifiedAt: .distantPast)
                if let fieldId = mappedPriceFieldId,
                   let raw = item.notes.first(where: { $0.fieldId == fieldId })?.value,
                   let parsed = PurchasePriceParser.parse(raw, defaultCurrency: defaultCurrency) {
                    details.purchaseAmount = parsed.amount
                    details.purchaseCurrency = parsed.currency
                }
                if let fieldId = mappedConditionFieldId,
                   let raw = item.notes.first(where: { $0.fieldId == fieldId })?.value,
                   let grade = RecordGrade(discogsValue: raw) {
                    details.mediaCondition = grade
                }
                guard !details.isEmpty else { continue }
                entries[item.instanceId] = details
                persist()
            }
        }
    }

    private func adoptFromCache() {
        guard let username = activeUsername,
              mappedPriceFieldId != nil || mappedConditionFieldId != nil else { return }
        adoptLegacyValues(from: LocalDataStore.shared.getAllCollectionItemsSync(username: username), username: username)
    }

    /// Relit les champs associés ; si l'un d'eux vient de changer, reprend les valeurs déjà en cache.
    private func refreshMapping() {
        guard let username = activeUsername else { return }
        let price = CollectionPreferencesStore.purchasePriceFieldId(for: username)
        let condition = CollectionPreferencesStore.mediaConditionFieldId(for: username)
        applyMapping(price: price, condition: condition)
    }

    /// Fixe les champs Discogs associés ; reprend les valeurs déjà en cache si l'un d'eux a changé.
    func applyMapping(price: Int?, condition: Int?) {
        guard price != mappedPriceFieldId || condition != mappedConditionFieldId else { return }
        mappedPriceFieldId = price
        mappedConditionFieldId = condition
        adoptFromCache()
    }

    // MARK: - Cycle de vie des exemplaires

    /// Reporte les données d'un identifiant provisoire (exemplaire créé hors ligne) sur l'identifiant
    /// définitif donné par Discogs.
    func remapInstanceId(from oldInstanceId: Int, to newInstanceId: Int) {
        guard oldInstanceId != newInstanceId, let details = entries[oldInstanceId] else { return }
        entries[oldInstanceId] = nil
        if entries[newInstanceId] == nil {
            entries[newInstanceId] = details
        }
        persist()
    }

    /// Oublie les données d'un exemplaire supprimé.
    func removeDetails(for instanceId: Int) {
        guard entries[instanceId] != nil else { return }
        entries[instanceId] = nil
        persist()
    }

    // MARK: - Persistance

    /// Regroupe plusieurs modifications en une seule écriture disque.
    func performBatchUpdate(_ updates: () -> Void) {
        batchDepth += 1
        updates()
        batchDepth -= 1
        if batchDepth == 0 && needsPersistAfterBatch {
            needsPersistAfterBatch = false
            persist()
        }
    }

    private func persist() {
        guard batchDepth == 0 else {
            needsPersistAfterBatch = true
            return
        }
        guard let username = activeUsername else { return }
        NotificationCenter.default.post(name: .copyDetailsChanged, object: nil)
        let stored = entries.map { StoredEntry(instanceId: $0.key, details: $0.value) }
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.key(for: username))
        }
    }
}


extension Notification.Name {
    /// Prix d'achat ou état d'un exemplaire modifié (voir `CopyDetailsStore`).
    static let copyDetailsChanged = Notification.Name("com.spinlog.copyDetailsChanged")
}
