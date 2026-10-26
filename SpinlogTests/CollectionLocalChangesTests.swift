import Foundation
import Testing
@testable import Spinlog

/// Mises à jour optimistes de la Collection (`CollectionLocalChanges`) et fusion des pages.
@MainActor
struct CollectionLocalChangesTests {
    private func item(_ instanceId: Int, release: Int = 1, folder: Int = 1) throws -> CollectionItem {
        let json: [String: Any] = [
            "id": release, "instance_id": instanceId, "folder_id": folder, "rating": 0,
            "date_added": "2024-01-15T10:00:00-07:00",
            "basic_information": ["id": release, "title": "T", "resource_url": "", "artists": [["id": 1, "name": "A"]]] as [String: Any]
        ]
        return try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private let folders = [
        CollectionFolder(id: 0, name: "All", count: 3),
        CollectionFolder(id: 1, name: "Uncategorized", count: 2),
        CollectionFolder(id: 2, name: "Jazz", count: 0)
    ]

    @Test func folderCountsNeverGoBelowZero() {
        let adjusted = CollectionLocalChanges.adjustingCounts(of: folders, by: [1: -1, 2: -1])
        #expect(adjusted.map(\.count) == [3, 1, 0])
    }

    @Test func moveLeavesAFolderFilteredViewAndUpdatesTheAllView() throws {
        let original = try item(10, folder: 1)
        let moved = original.moved(toFolderId: 2)
        #expect(CollectionLocalChanges.itemsAfterMove([original], original: original, moved: moved, selectedFolderId: 1).isEmpty)
        let inAll = CollectionLocalChanges.itemsAfterMove([original], original: original, moved: moved, selectedFolderId: 0)
        #expect(inAll.first?.folderId == 2)
    }

    @Test func revertingAMoveRestoresTheOriginalView() throws {
        let original = try item(10, folder: 1)
        let moved = original.moved(toFolderId: 2)
        // Vue du dossier de départ : l'exemplaire en avait été retiré, il y revient.
        let back = CollectionLocalChanges.itemsAfterRevertingMove([], original: original, moved: moved, selectedFolderId: 1)
        #expect(back.map(\.folderId) == [1])
        // Vue du dossier d'arrivée : il en ressort.
        #expect(CollectionLocalChanges.itemsAfterRevertingMove([moved], original: original, moved: moved, selectedFolderId: 2).isEmpty)
    }

    @Test func pagesMergeWithoutDuplicatesOrPhantoms() throws {
        let shown = [try item(10), try item(11)]
        let page = [try item(11), try item(12), try item(0), try item(5, release: 5)]
        let merged = CollectionLocalChanges.merging(page: page, into: shown, append: true)
        #expect(merged.map(\.instanceId) == [10, 11, 12])
        let replaced = CollectionLocalChanges.merging(page: page, into: shown, append: false)
        #expect(replaced.map(\.instanceId) == [11, 12])
    }

    @Test func externalAddShowsTheCopyOnlyInItsFolderOrAll() throws {
        let added = try item(20, folder: 2)
        let inOtherFolder = CollectionLocalChanges.afterExternalAdd(of: added, items: [], folders: folders, selectedFolderId: 1)
        #expect(inOtherFolder.items == nil)
        #expect(inOtherFolder.folders.map(\.count) == [4, 2, 1])
        let inAll = CollectionLocalChanges.afterExternalAdd(of: added, items: [try item(10)], folders: folders, selectedFolderId: 0)
        #expect(inAll.items?.first?.instanceId == 20)
    }

    @Test func externalRemovalOfAWholeReleaseRemovesEveryCopy() throws {
        let items = [try item(10, release: 1), try item(11, release: 1), try item(12, release: 2)]
        let all = CollectionLocalChanges.afterExternalRemoval(releaseId: 1, instanceId: nil, items: items, folders: folders, selectedFolderId: 1)
        #expect(all.items.map(\.instanceId) == [12])
        #expect(all.folders.map(\.count) == [2, 1, 0])
        let one = CollectionLocalChanges.afterExternalRemoval(releaseId: 1, instanceId: 11, items: items, folders: folders, selectedFolderId: nil)
        #expect(one.items.map(\.instanceId) == [10, 12])
    }

    @Test func fieldValueIsReplacedOrAdded() {
        let notes = [CollectionFieldValue(fieldId: 1, value: "VG")]
        #expect(notes.settingValue("NM", forFieldId: 1).map(\.value) == ["NM"])
        #expect(notes.settingValue("20 EUR", forFieldId: 3).map(\.fieldId) == [1, 3])
    }

    @Test func onlyFailuresQueuedForLaterGetAMessage() {
        #expect(DiscogsWriteOutcome.queuedAfterFailure.failureQueuedMessage != nil)
        for outcome in [DiscogsWriteOutcome.done, .queuedOffline, .refused] {
            #expect(outcome.failureQueuedMessage == nil)
        }
    }

    @Test func temporaryInstanceIdsAreNegativeAndUnique() {
        let first = DiscogsWriteService.makeTemporaryInstanceId()
        let second = DiscogsWriteService.makeTemporaryInstanceId()
        #expect(first < 0)
        #expect(second < first)
    }
}
