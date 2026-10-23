import Testing
@testable import Spinlog

/// Règle de retour utilisateur après un ajout ou un retrait (haptique de succès contre choc léger).
@MainActor
struct LibraryFeedbackEventTests {
    @Test func additionsAreAdditions() {
        #expect(LibraryFeedbackEvent.Kind.addedToCollection.isAddition)
        #expect(LibraryFeedbackEvent.Kind.addedToWantlist.isAddition)
    }

    @Test func removalsAreNotAdditions() {
        #expect(!LibraryFeedbackEvent.Kind.removedFromCollection.isAddition)
        #expect(!LibraryFeedbackEvent.Kind.removedFromWantlist.isAddition)
    }

    /// Deux ajouts successifs doivent rester distincts, sans quoi l'écran ne réagirait pas au second.
    @Test func successiveIdenticalEventsAreDistinct() {
        #expect(LibraryFeedbackEvent(.addedToCollection) != LibraryFeedbackEvent(.addedToCollection))
    }
}
