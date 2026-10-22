import Testing
@testable import Spinlog

/// Pastilles de plus-value (« Mon exemplaire ») et jauge de seuil (« Alerte de prix »).
struct PriceSheetModelsTests {
    @Test func gainIsPositiveWhenEstimateExceedsPurchase() {
        let summary = GainSummary(purchase: 20, estimate: 35)
        #expect(summary.gain == 15)
        #expect(summary.isGain)
        #expect(summary.percent == 0.75)
    }

    @Test func gainIsNegativeWhenEstimateIsBelowPurchase() {
        let summary = GainSummary(purchase: 40, estimate: 30)
        #expect(summary.gain == -10)
        #expect(!summary.isGain)
        #expect(summary.percent == -0.25)
    }

    @Test func zeroPurchaseHasNoPercentage() {
        let summary = GainSummary(purchase: 0, estimate: 12)
        #expect(summary.percent == nil)
        #expect(summary.gain == 12)
    }

    @Test func targetIsReachedWhenAnOfferIsAtOrBelowIt() {
        #expect(PriceAlertGaugeModel(target: 30, lowest: 25).isReached)
        #expect(PriceAlertGaugeModel(target: 30, lowest: 30).isReached)
        #expect(!PriceAlertGaugeModel(target: 30, lowest: 36).isReached)
        #expect(!PriceAlertGaugeModel(target: 30, lowest: nil).isReached)
    }

    @Test func gapIsMeasuredAgainstTheLowestOffer() {
        let model = PriceAlertGaugeModel(target: 30, lowest: 40)
        #expect(model.gap == 10)
        #expect(model.gapPercent == 0.25)
        #expect(PriceAlertGaugeModel(target: 30, lowest: 25).gap == 0)
        #expect(PriceAlertGaugeModel(target: 30, lowest: nil).gap == nil)
    }

    @Test func positionsStayWithinTheScale() {
        let model = PriceAlertGaugeModel(target: 30, lowest: 50)
        #expect(model.upperBound == 62.5)
        #expect(model.position(of: 0) == 0)
        #expect(model.position(of: 50) == 0.8)
        #expect(model.position(of: 1_000) == 1)
        #expect(model.position(of: -5) == 0)
        // Aucun repère : l'échelle ne s'effondre pas.
        #expect(PriceAlertGaugeModel(target: 0, lowest: nil).upperBound == 1)
    }
}
