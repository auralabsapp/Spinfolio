import Testing
import Foundation
@testable import Spinlog

struct PaywallLegalTextTests {
    @Test func yearlyRenewalMentionsPrice() {
        let text = PaywallLegalText.renewal(kind: .yearly, price: "17,99 €", trial: nil)
        #expect(text.contains("17,99 €"))
    }

    @Test func monthlyRenewalMentionsPrice() {
        let text = PaywallLegalText.renewal(kind: .monthly, price: "1,99 €", trial: nil)
        #expect(text.contains("1,99 €"))
    }

    @Test func trialIsMentionedWithTheYearlyPrice() {
        let text = PaywallLegalText.renewal(kind: .yearly, price: "17,99 €", trial: "1 semaine d'essai gratuit")
        #expect(text.contains("1 semaine d'essai gratuit"))
        #expect(text.contains("17,99 €"))
    }

    @Test func monthlyNeverMentionsATrial() {
        let text = PaywallLegalText.renewal(kind: .monthly, price: "1,99 €", trial: "1 semaine d'essai gratuit")
        #expect(!text.contains("essai"))
    }
}
