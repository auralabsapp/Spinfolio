import Testing
@testable import Spinlog

/// Retrait de disques de l'instantané du widget, sans relire toute la collection.
@MainActor
struct WidgetSnapshotRemovalTests {
    private func item(_ releaseId: Int) -> RandomAlbumSnapshotItem {
        RandomAlbumSnapshotItem(releaseId: releaseId, title: "Disque \(releaseId)", artistNames: "Artiste", coverURL: nil)
    }

    @Test func removedReleasesLeaveTheSnapshotAndOrderIsKept() {
        let snapshot = [item(1), item(2), item(3), item(4)]
        let pruned = LocalDataStore.widgetSnapshot(snapshot, removing: [2, 4])
        #expect(pruned?.map(\.releaseId) == [1, 3])
    }

    @Test func nothingToRewriteWhenNoReleaseWasInTheSnapshot() {
        // Évite de réécrire l'App Group et de recharger le widget pour rien.
        #expect(LocalDataStore.widgetSnapshot([item(1)], removing: [9]) == nil)
        #expect(LocalDataStore.widgetSnapshot([], removing: [1]) == nil)
    }

    @Test func lastReleaseRemovedGivesAnEmptySnapshot() {
        #expect(LocalDataStore.widgetSnapshot([item(1)], removing: [1])?.isEmpty == true)
    }
}
