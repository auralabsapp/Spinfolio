import Foundation
import Testing
@testable import Spinlog

/// Sessions d'écoute reçues d'iCloud ou restaurées depuis une sauvegarde (`ListeningLogStore`).
struct ListeningLogMergeTests {
    private func session(_ releaseId: Int, at seconds: TimeInterval, id: UUID = UUID()) -> ListeningSession {
        ListeningSession(id: id, releaseId: releaseId, timestamp: Date(timeIntervalSince1970: seconds))
    }

    @Test func receivingTheSameSessionTwiceDoesNotDuplicateIt() {
        let remote = session(1, at: 100)
        let once = ListeningLogStore.applying(remote, to: [], sorted: true)
        let twice = ListeningLogStore.applying(remote, to: once, sorted: true)
        #expect(twice == [remote])
    }

    @Test func updatedSessionReplacesTheOldOneAndKeepsNewestFirst() {
        let id = UUID()
        let old = session(1, at: 100, id: id)
        let other = session(2, at: 200)
        let updated = session(1, at: 300, id: id)

        let result = ListeningLogStore.applying(updated, to: [other, old], sorted: true)
        #expect(result == [updated, other])
    }

    @Test func unsortedApplyKeepsArrivalOrderForBatches() {
        let first = session(1, at: 100)
        let second = session(2, at: 200)
        let result = ListeningLogStore.applying(second, to: [first], sorted: false)
        #expect(result == [first, second])
    }

    @Test func restoreOnlyAddsMissingSessions() {
        let kept = session(1, at: 100)
        let imported = session(2, at: 200)
        let (merged, added) = ListeningLogStore.mergingRestored([kept, imported, imported], into: [kept])
        #expect(merged == [imported, kept])
        #expect(added == [imported.id])
    }
}
