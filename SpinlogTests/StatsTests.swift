import Foundation
import Testing
@testable import Spinlog

/// Statistiques : hauteur des classements d'écoute (5 lignes visibles, le reste en défilant).
@MainActor
struct StatsTests {
    @Test func showsExactlyFiveMeasuredRows() {
        // 20 lignes mesurées à 600 pt au total → 5 lignes = 150 pt, quelle que soit l'estimation.
        #expect(StatsView.cappedListHeight(contentHeight: 600, rowCount: 20, estimatedRowHeight: 56) == 150)
    }

    @Test func shortListShowsAllRows() {
        #expect(StatsView.cappedListHeight(contentHeight: 210, rowCount: 3, estimatedRowHeight: 56) == 210)
    }

    @Test func fallsBackToEstimateBeforeMeasurement() {
        #expect(StatsView.cappedListHeight(contentHeight: 0, rowCount: 12, estimatedRowHeight: 56) == 280)
        #expect(StatsView.cappedListHeight(contentHeight: 0, rowCount: 0, estimatedRowHeight: 56) == 0)
    }
}
