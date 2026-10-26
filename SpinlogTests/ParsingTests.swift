import Foundation
import Testing
@testable import Spinlog

@MainActor
struct PurchasePriceParserTests {
    @Test(arguments: [
        ("25,50 €", 25.5, "EUR"),
        ("1.234,56 €", 1234.56, "EUR"),
        ("$1,234.56", 1234.56, "USD"),
        ("$960.00", 960.0, "USD"),
        ("USD 30", 30.0, "USD"),
        ("£12", 12.0, "GBP"),
        ("12.5", 12.5, "CHF")
    ])
    func parsesAmountAndCurrency(raw: String, amount: Double, currency: String) throws {
        let result = try #require(PurchasePriceParser.parse(raw, defaultCurrency: "CHF"))
        #expect(abs(result.amount - amount) < 0.001)
        #expect(result.currency == currency)
    }

    @Test(arguments: ["", "   ", "gratuit"])
    func rejectsInputWithoutAmount(raw: String) {
        #expect(PurchasePriceParser.parse(raw, defaultCurrency: "EUR") == nil)
    }

    @Test func canonicalStringUsesTwoDecimalsAndUppercasedCurrency() {
        #expect(PurchasePriceParser.canonicalString(amount: 25.5, currency: "eur") == "25.50 EUR")
    }
}

@MainActor
struct DiscogsDateParsingTests {
    @Test func parsesDiscogsDateWithTimeZoneOffset() throws {
        // Format renvoyé par Discogs pour `date_added` : 10:00 à UTC-7, soit 17:00 UTC.
        let date = try #require(DiscogsDateParsing.dateAdded(from: "2023-03-01T10:00:00-07:00"))
        #expect(date == Date(timeIntervalSince1970: 1_677_690_000))
    }

    @Test func parsesDateWithoutTimeZoneOffset() {
        #expect(DiscogsDateParsing.dateAdded(from: "2023-03-01T17:00:00Z") == Date(timeIntervalSince1970: 1_677_690_000))
    }

    @Test(arguments: ["", "hier", "2023-03-01", "01/03/2023 10:00"])
    func rejectsNonISODates(raw: String) {
        #expect(DiscogsDateParsing.dateAdded(from: raw) == nil)
    }

    @Test func repeatedParsingReturnsTheSameDate() {
        // Le deuxième appel passe par le cache mémoïsé : il doit rendre exactement la même valeur.
        let raw = "2024-12-24T08:30:00-08:00"
        #expect(DiscogsDateParsing.dateAdded(from: raw) == DiscogsDateParsing.dateAdded(from: raw))
    }
}

struct DiscogsDurationTests {
    @Test(arguments: [("3:45", 225), ("0:07", 7), ("12:00", 720), ("61:30", 3690)])
    func parsesMinutesSeconds(raw: String, seconds: Int) {
        #expect(raw.discogsDurationSeconds == seconds)
    }

    @Test(arguments: ["", "345", "3'45", "abc", "3:", ":45", "1:2:3"])
    func rejectsMalformedDurations(raw: String) {
        #expect(raw.discogsDurationSeconds == nil)
    }

    @Test(arguments: [(225, "3:45"), (7, "0:07"), (0, "0:00"), (3600, "60:00")])
    func formatsSecondsAsMinutesSeconds(seconds: Int, expected: String) {
        #expect(seconds.formattedAsMinutesSeconds == expected)
    }
}

/// Pastille de plus-value masquée (compte non Premium) : même format que le montant réel.
struct MaskedGainAmountTests {
    @Test func digitsAreHiddenButTheCurrencyStays() {
        // Langue fixée : le symbole dépend sinon de la langue du Simulateur.
        let masked = SwipeableInstanceRow.maskedAmount(currency: "EUR", locale: Locale(identifier: "fr_FR"))
        #expect(masked.contains("€"))
        #expect(masked.contains("?"))
        #expect(!masked.contains("0"))
        #expect(!masked.contains("%"))
    }
}
