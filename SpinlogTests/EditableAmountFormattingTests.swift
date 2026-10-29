import Testing
import Foundation
@testable import Spinlog

struct EditableAmountFormattingTests {
    @Test func usesDecimalSeparatorOfLocale() {
        #expect(PurchasePriceParser.editableAmountString(12.5, locale: Locale(identifier: "fr_FR")) == "12,50")
        #expect(PurchasePriceParser.editableAmountString(12.5, locale: Locale(identifier: "en_US")) == "12.50")
    }

    @Test func neverGroupsThousands() {
        #expect(PurchasePriceParser.editableAmountString(1234.5, locale: Locale(identifier: "fr_FR")) == "1234,50")
    }

    @MainActor @Test func formattedEditableAmountIsReadBackByParser() {
        let text = PurchasePriceParser.editableAmountString(25.5, locale: Locale(identifier: "fr_FR"))
        #expect(PurchasePriceParser.parse(text, defaultCurrency: "EUR")?.amount == 25.5)
    }
}
