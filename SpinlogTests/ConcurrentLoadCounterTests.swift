import Testing
@testable import Spinlog

/// Chargements simultanés de la Collection : seul le dernier en cours déclare le premier chargement
/// terminé, et un chargement interrompu sait si un autre prend le relais.
struct ConcurrentLoadCounterTests {
    @Test func aLoneLoadIsTheLastOne() {
        var counter = ConcurrentLoadCounter()
        counter.begin()
        #expect(!counter.othersInFlight)
        let isLast = counter.end()
        #expect(isLast)
    }

    @Test func anInterruptedLoadIsNotTheLastWhileAnotherRuns() {
        var counter = ConcurrentLoadCounter()
        counter.begin() // chargement de l'ancienne vue
        counter.begin() // chargement de la nouvelle vue
        #expect(counter.othersInFlight)
        let interruptedIsLast = counter.end() // l'interrompu se termine : le premier chargement n'est pas fini
        #expect(!interruptedIsLast)
        #expect(!counter.othersInFlight)
        let newOneIsLast = counter.end() // le nouveau se termine : c'est le dernier
        #expect(newOneIsLast)
    }

    @Test func endingMoreThanBegunNeverGoesNegative() {
        var counter = ConcurrentLoadCounter()
        let firstIsLast = counter.end()
        #expect(firstIsLast)
        counter.begin()
        let secondIsLast = counter.end()
        #expect(secondIsLast)
    }
}
