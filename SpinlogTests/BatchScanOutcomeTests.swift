import Testing
@testable import Spinlog

/// Bilan du scan par lot : un ajout mis en file ou refusé ne doit plus être compté comme réussi.
@MainActor
struct BatchScanOutcomeTests {
    @Test func noMessageOnlineMeansAdded() {
        #expect(BatchScanViewModel.addOutcome(forActionMessage: nil, isOffline: false) == .added)
    }

    @Test func offlineOrUnavailableDiscogsMeansQueued() {
        #expect(BatchScanViewModel.addOutcome(forActionMessage: nil, isOffline: true) == .queued)
        #expect(BatchScanViewModel.addOutcome(forActionMessage: AppMessages.discogsUnavailableQueued, isOffline: false) == .queued)
    }

    @Test func anyOtherMessageMeansFailed() {
        #expect(BatchScanViewModel.addOutcome(forActionMessage: AppMessages.addFailed, isOffline: false) == .failed)
        #expect(BatchScanViewModel.addOutcome(forActionMessage: AppMessages.offlineStaleAddBlocked, isOffline: true) == .failed)
        #expect(BatchScanViewModel.addOutcome(forActionMessage: AppMessages.loginRequiredForCollection, isOffline: false) == .failed)
    }
}
