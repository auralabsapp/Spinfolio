import Testing
@testable import Spinlog

/// Bilan du scan par lot : un ajout mis en file ou refusé ne doit plus être compté comme réussi.
@MainActor
struct BatchScanOutcomeTests {
    @Test func noMessageMeansAdded() {
        #expect(BatchScanViewModel.addOutcome(forActionMessage: nil) == .added)
    }

    @Test func offlineOrUnavailableDiscogsMeansQueued() {
        #expect(BatchScanViewModel.addOutcome(forActionMessage: AppMessages.offlineAddQueued) == .queued)
        #expect(BatchScanViewModel.addOutcome(forActionMessage: AppMessages.discogsUnavailableQueued) == .queued)
    }

    @Test func anyOtherMessageMeansFailed() {
        #expect(BatchScanViewModel.addOutcome(forActionMessage: AppMessages.addFailed) == .failed)
        #expect(BatchScanViewModel.addOutcome(forActionMessage: AppMessages.offlineStaleAddBlocked) == .failed)
        #expect(BatchScanViewModel.addOutcome(forActionMessage: AppMessages.loginRequiredForCollection) == .failed)
    }
}
