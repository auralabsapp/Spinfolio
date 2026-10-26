import Foundation
import Testing
@testable import Spinlog

/// Clé de tri des artistes du meuble physique (`shelfArtistSortKey`), fonction Premium.
struct ShelfSortStrategyTests {
    @Test func discogsDisambiguationNumberIsIgnored() {
        #expect("Bill Evans (3)".shelfArtistSortKey() == "Bill Evans")
        #expect(ArtistShelfSortHelper.cleanDiscogsSuffix("Prince (2)") == "Prince")
    }

    @Test func initialArticleMovesToTheEndOnlyWhenIgnored() {
        #expect("The Beatles".shelfArtistSortKey(ignoreArticles: true) == "Beatles, The")
        #expect("The Beatles".shelfArtistSortKey(ignoreArticles: false) == "The Beatles")
        #expect("L'Impératrice".shelfArtistSortKey(ignoreArticles: true) == "Impératrice, L'")
        #expect("Les Négresses Vertes".shelfArtistSortKey(ignoreArticles: true) == "Négresses Vertes, Les")
    }

    @Test(arguments: [
        ("David Bowie", "Bowie, David"),
        ("Bill Evans (3)", "Evans, Bill"),
        ("Stevie Ray Vaughan", "Vaughan, Stevie Ray"),
        ("Ludwig van Beethoven", "Beethoven, Ludwig van"),
        ("Maxime Le Forestier", "Le Forestier, Maxime"),
        ("Sammy Davis Jr.", "Davis, Sammy Jr.")
    ])
    func soloArtistsAreSortedByLastName(name: String, expected: String) {
        #expect(name.shelfArtistSortKey(sortByLastName: true) == expected)
    }

    @Test(arguments: ["Pink Floyd", "Dave Matthews Band", "Miles Davis Quintet", "Bowie, David"])
    func bandsAndAlreadyInvertedNamesAreKept(name: String) {
        #expect(name.shelfArtistSortKey(sortByLastName: true) == name)
    }

    @Test func knownBandKeepsItsArticleAtTheEnd() {
        #expect("The Rolling Stones".shelfArtistSortKey(ignoreArticles: true, sortByLastName: true) == "Rolling Stones, The")
    }

    @Test func userOverrideWinsOverEveryRule() {
        let overrides = ["Prince": "Nelson, Prince"]
        #expect("Prince (2)".shelfArtistSortKey(sortByLastName: true, overrides: overrides) == "Nelson, Prince")
        // Un artiste sans surcharge suit toujours les règles automatiques.
        #expect("David Bowie".shelfArtistSortKey(sortByLastName: true, overrides: overrides) == "Bowie, David")
    }

    @Test func emptyNameGivesEmptyKey() {
        #expect("".shelfArtistSortKey() == "")
        #expect("  (2) ".shelfArtistSortKey() == "")
    }
}
