import Foundation

/// Une valeur à écrire dans le store : un prix, un état, ou les deux, pour un exemplaire.
struct CopyDetailsImportOperation: Equatable {
    let instanceId: Int
    var price: (amount: Double, currency: String)?
    var grade: RecordGrade?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.instanceId == rhs.instanceId
            && lhs.price?.amount == rhs.price?.amount && lhs.price?.currency == rhs.price?.currency
            && lhs.grade == rhs.grade
    }
}

/// Import du prix d'achat et de l'état du disque depuis des champs personnalisés Discogs : lecture
/// stricte des valeurs et plan d'import (aperçu chiffré, règles de conflit), sans rien écrire. Voir
/// `CopyDetailsImportViewModel` pour le déroulé et `CopyDetailsStore.applyImport` pour l'écriture.
enum CopyDetailsImport {
    // MARK: - Lecture stricte

    enum PriceReading: Equatable {
        case empty
        /// `hasCurrency` : la valeur portait elle-même sa devise (symbole ou code) ; sinon la devise
        /// choisie pour les prix sans devise a été appliquée.
        case valid(amount: Double, currency: String, hasCurrency: Bool)
        case unreadable
    }

    enum GradeReading: Equatable {
        case empty
        case valid(RecordGrade)
        case unreadable
    }

    private static let symbols: [(symbol: String, code: String)] = [("€", "EUR"), ("$", "USD"), ("£", "GBP"), ("¥", "JPY")]

    /// Un montant seul (« 24,99 »), avec un symbole (« €24.99 », « 24,99 € ») ou avec un code de devise
    /// de l'app (« USD 30 », « 30 EUR »). Tout le reste est illisible : texte autour du nombre,
    /// plusieurs nombres, montant négatif, devise inconnue. Plus strict que `PurchasePriceParser.parse`,
    /// qui prend le premier nombre d'un texte libre : ici, mieux vaut ne pas importer que se tromper.
    static func readPrice(_ raw: String, unspecifiedCurrency: String) -> PriceReading {
        let text = raw
            .replacingOccurrences(of: "\u{a0}", with: " ")
            .replacingOccurrences(of: "\u{202f}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }

        var body = text
        var currency: String?
        if let split = splitCurrency(text) {
            currency = split.code
            body = split.rest
        }
        guard let amount = parseAmount(body) else { return .unreadable }
        return .valid(amount: amount, currency: currency ?? unspecifiedCurrency, hasCurrency: currency != nil)
    }

    static func readGrade(_ raw: String) -> GradeReading {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        return RecordGrade(discogsValue: trimmed).map(GradeReading.valid) ?? .unreadable
    }

    /// Retire un symbole ou un code de devise en tête ou en fin de texte (un seul).
    private static func splitCurrency(_ text: String) -> (code: String, rest: String)? {
        for (symbol, code) in symbols {
            if text.hasPrefix(symbol) { return (code, String(text.dropFirst(symbol.count))) }
            if text.hasSuffix(symbol) { return (code, String(text.dropLast(symbol.count))) }
        }
        let upper = text.uppercased()
        for code in PurchasePriceParser.supportedCurrencies {
            if upper.hasPrefix(code) { return (code, String(text.dropFirst(code.count))) }
            if upper.hasSuffix(code) { return (code, String(text.dropLast(code.count))) }
        }
        return nil
    }

    /// Nombre décimal : chiffres, séparateur décimal (virgule ou point, 1 ou 2 décimales), séparateurs
    /// de milliers (espaces, ou virgule ou point par groupes de 3 chiffres). Sans signe.
    private static func parseAmount(_ body: String) -> Double? {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        let plain = /\d+([.,]\d{1,2})?/
        let spaced = /\d{1,3}( \d{3})+([.,]\d{1,2})?/
        let grouped = /\d{1,3}([.,]\d{3})+([.,]\d{1,2})?/
        guard trimmed.wholeMatch(of: plain) != nil
            || trimmed.wholeMatch(of: spaced) != nil
            || trimmed.wholeMatch(of: grouped) != nil else { return nil }

        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        // Dernier séparateur suivi de 1 ou 2 chiffres : c'est la décimale ; sinon, que des milliers.
        if let lastSeparator = compact.lastIndex(where: { $0 == "." || $0 == "," }) {
            let decimals = compact[compact.index(after: lastSeparator)...]
            let integerPart = compact[..<lastSeparator].filter { $0 != "." && $0 != "," }
            if decimals.count <= 2 {
                // « 12,345,6 » : la même virgule ne peut être à la fois milliers et décimale.
                if let firstSeparator = compact.firstIndex(where: { $0 == "." || $0 == "," }),
                   firstSeparator != lastSeparator, compact[firstSeparator] == compact[lastSeparator] {
                    return nil
                }
                return Double("\(integerPart).\(decimals)")
            }
            return Double(compact.filter { $0 != "." && $0 != "," })
        }
        return Double(compact)
    }

    // MARK: - Plan d'import

    /// Valeur lue sur Discogs qui n'a pas pu être importée.
    struct UnreadableValue: Identifiable, Equatable {
        let instanceId: Int
        let title: String
        let raw: String
        var id: Int { instanceId }
    }

    /// Bilan d'un champ (prix ou état).
    struct FieldSummary: Equatable {
        /// Valeur lisible et exemplaire sans valeur locale : sera importée.
        var toImport = 0
        /// Valeur lisible identique à celle de l'app.
        var upToDate = 0
        /// Valeur lisible différente de celle de l'app : importée seulement avec « Remplacer ».
        var conflicts = 0
        var unreadable: [UnreadableValue] = []
        /// Exemplaires dont le champ est vide sur Discogs.
        var emptyOnDiscogs = 0
    }

    struct Sample: Equatable {
        let title: String
        let raw: String
        let interpreted: String
    }

    struct Plan {
        var price = FieldSummary()
        var condition = FieldSummary()
        /// Prix lisibles par devise, devise appliquée comprise.
        var currencies: [String: Int] = [:]
        /// Prix lisibles qui n'indiquaient aucune devise.
        var withoutCurrency = 0
        /// Quelques valeurs lues, pour repérer un mauvais choix de champ avant d'importer.
        var samples: [Sample] = []
        fileprivate var candidates: [Candidate] = []

        /// Rien à écrire, même en remplaçant.
        var isEmpty: Bool { operations(replacing: true).isEmpty }

        /// Écritures à faire : les valeurs lisibles pour les exemplaires sans valeur locale, plus celles
        /// qui diffèrent de la valeur locale si `replacing`. Une valeur vide ou illisible n'efface
        /// jamais rien : elle n'apparaît pas ici.
        func operations(replacing: Bool) -> [CopyDetailsImportOperation] {
            candidates.compactMap { candidate in
                var operation = CopyDetailsImportOperation(instanceId: candidate.instanceId)
                if let price = candidate.price {
                    let local = candidate.localPrice
                    let isSame = local?.amount == price.amount && local?.currency == price.currency
                    if !isSame, local == nil || replacing { operation.price = price }
                }
                if let grade = candidate.grade, grade != candidate.localGrade {
                    if candidate.localGrade == nil || replacing { operation.grade = grade }
                }
                return operation.price == nil && operation.grade == nil ? nil : operation
            }
        }
    }

    fileprivate struct Candidate {
        let instanceId: Int
        var price: (amount: Double, currency: String)?
        var grade: RecordGrade?
        let localPrice: (amount: Double, currency: String)?
        let localGrade: RecordGrade?
    }

    /// Construit le plan à partir des exemplaires lus sur Discogs et des champs choisis. Aucune
    /// écriture : `existing` donne ce que l'app garde déjà pour un exemplaire.
    static func plan(
        items: [CollectionItem],
        priceFieldId: Int?,
        conditionFieldId: Int?,
        unspecifiedCurrency: String,
        existing: (Int) -> CopyDetails?
    ) -> Plan {
        var plan = Plan()
        for item in items where item.instanceId > 0 && item.instanceId != item.releaseId {
            let local = existing(item.instanceId)
            var candidate = Candidate(
                instanceId: item.instanceId, price: nil, grade: nil,
                localPrice: local?.purchasePrice, localGrade: local?.mediaCondition
            )
            var sampleRaw: [String] = []

            if let priceFieldId {
                let raw = item.value(forFieldId: priceFieldId)
                switch readPrice(raw, unspecifiedCurrency: unspecifiedCurrency) {
                case .empty:
                    plan.price.emptyOnDiscogs += 1
                case .unreadable:
                    plan.price.unreadable.append(UnreadableValue(instanceId: item.instanceId, title: item.basicInformation.title, raw: raw))
                case .valid(let amount, let currency, let hasCurrency):
                    candidate.price = (amount, currency)
                    plan.currencies[currency, default: 0] += 1
                    if !hasCurrency { plan.withoutCurrency += 1 }
                    if let localPrice = candidate.localPrice {
                        if localPrice.amount == amount && localPrice.currency == currency { plan.price.upToDate += 1 } else { plan.price.conflicts += 1 }
                    } else {
                        plan.price.toImport += 1
                    }
                    sampleRaw.append(raw)
                }
            }

            if let conditionFieldId {
                let raw = item.value(forFieldId: conditionFieldId)
                switch readGrade(raw) {
                case .empty:
                    plan.condition.emptyOnDiscogs += 1
                case .unreadable:
                    plan.condition.unreadable.append(UnreadableValue(instanceId: item.instanceId, title: item.basicInformation.title, raw: raw))
                case .valid(let grade):
                    candidate.grade = grade
                    if let localGrade = candidate.localGrade {
                        if localGrade == grade { plan.condition.upToDate += 1 } else { plan.condition.conflicts += 1 }
                    } else {
                        plan.condition.toImport += 1
                    }
                    sampleRaw.append(raw)
                }
            }

            if plan.samples.count < 3, !sampleRaw.isEmpty {
                plan.samples.append(Sample(
                    title: item.basicInformation.title,
                    raw: sampleRaw.joined(separator: " · "),
                    interpreted: interpretedText(for: candidate)
                ))
            }
            if candidate.price != nil || candidate.grade != nil { plan.candidates.append(candidate) }
        }
        return plan
    }

    private static func interpretedText(for candidate: Candidate) -> String {
        var parts: [String] = []
        if let price = candidate.price { parts.append(price.amount.formatted(.currency(code: price.currency))) }
        if let grade = candidate.grade { parts.append(grade.discogsLabel) }
        return parts.joined(separator: " · ")
    }
}
