import Foundation

/// Parsing et formatage des prix d'achat : que ce soit une saisie libre de l'utilisateur ou un
/// montant déjà formaté par Discogs (`collection/value` renvoie des chaînes du type `"$960.00"`).
enum PurchasePriceParser {
    /// Devises proposées par l'app (alignées sur le sélecteur des réglages et de la feuille d'édition).
    static let supportedCurrencies = ["EUR", "USD", "GBP", "JPY", "CAD", "CHF"]

    private static let symbolToCurrency: [String: String] = [
        "€": "EUR", "$": "USD", "£": "GBP", "¥": "JPY"
    ]

    /// Extrait un montant + une devise d'un texte libre (ex. `"25,50 €"`, `"USD 30"`, `"12.5"`).
    /// Retombe sur `defaultCurrency` si aucune devise n'est identifiable dans le texte.
    static func parse(_ raw: String, defaultCurrency: String) -> (amount: Double, currency: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let amount = extractAmount(from: trimmed) else { return nil }
        let currency = extractCurrency(from: trimmed) ?? defaultCurrency
        return (amount, currency)
    }

    /// Parse un montant déjà formaté par Discogs (symbole devant le nombre, sans espace,
    /// séparateur décimal toujours un point : ex. `"$960.00"`).
    static func parseFormattedDiscogsAmount(_ raw: String, defaultCurrency: String = "USD") -> (amount: Double, currency: String)? {
        parse(raw, defaultCurrency: defaultCurrency)
    }

    /// Montant pour un champ de saisie : séparateur décimal du système (virgule ou point), deux
    /// décimales, sans séparateur de milliers. La saisie reste relue par `parse` (qui accepte les deux
    /// séparateurs) ; seul le format *envoyé à Discogs* reste `canonicalString`.
    nonisolated static func editableAmountString(_ amount: Double, locale: Locale = .autoupdatingCurrent) -> String {
        amount.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(locale))
    }

    /// Formate un montant + devise sous la forme canonique attendue par Discogs à l'écriture
    /// d'un champ personnalisé (ex. `"25.50 EUR"`).
    static func canonicalString(amount: Double, currency: String) -> String {
        "\(String(format: "%.2f", amount)) \(currency.uppercased())"
    }

    // MARK: - Extraction

    private static func extractAmount(from text: String) -> Double? {
        var cleaned = text.replacingOccurrences(of: "\u{a0}", with: " ")

        let hasComma = cleaned.contains(",")
        let hasDot = cleaned.contains(".")

        if hasComma && hasDot {
            // Le séparateur décimal est celui qui apparaît en dernier ; l'autre est un séparateur
            // de milliers à retirer (ex. "1,234.56" -> "1234.56", "1.234,56" -> "1234.56").
            if let lastComma = cleaned.lastIndex(of: ","), let lastDot = cleaned.lastIndex(of: ".") {
                if lastComma > lastDot {
                    cleaned.removeAll { $0 == "." }
                    cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
                } else {
                    cleaned.removeAll { $0 == "," }
                }
            }
        } else if hasComma {
            // Une seule virgule sans point : c'est un séparateur décimal (convention FR).
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        }

        guard let match = cleaned.firstMatch(of: /\d+(\.\d+)?/) else { return nil }
        return Double(cleaned[match.range])
    }

    private static func extractCurrency(from text: String) -> String? {
        for (symbol, code) in symbolToCurrency where text.contains(symbol) {
            return code
        }
        let upper = text.uppercased()
        for code in supportedCurrencies {
            if upper.range(of: "\\b\(code)\\b", options: .regularExpression) != nil {
                return code
            }
        }
        return nil
    }
}
