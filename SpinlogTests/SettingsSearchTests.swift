import Testing
@testable import Spinlog

/// Recherche de l'écran d'accueil de Réglages : correspondance (casse, accents, plusieurs mots) et index.
@MainActor
struct SettingsSearchTests {
    private func ids(_ query: String, authenticated: Bool = true, premium: Bool = true) -> Set<String> {
        Set(SettingsSearchIndex.results(for: query, isAuthenticated: authenticated, isPremium: premium).map(\.id))
    }

    @Test func emptyOrBlankQueryMatchesNothing() {
        #expect(ids("").isEmpty)
        #expect(ids("   ").isEmpty)
    }

    @Test func matchingIgnoresCaseAndAccents() {
        #expect(SettingsSearchMatcher.matches(query: "ETAT", haystack: ["Champ état de l'album"]))
        #expect(SettingsSearchMatcher.matches(query: "theme", haystack: ["Couleur du thème"]))
    }

    @Test func everyWordMustMatch() {
        #expect(SettingsSearchMatcher.matches(query: "champ prix", haystack: ["Champ prix d'achat"]))
        #expect(!SettingsSearchMatcher.matches(query: "champ euro", haystack: ["Champ prix d'achat"]))
    }

    /// Les mots-clés couvrent le français et l'anglais, quelle que soit la langue de l'app.
    @Test func keywordsWorkInBothLanguages() {
        #expect(ids("cloud").contains("iCloud"))
        #expect(ids("dark").contains("display"))
        #expect(ids("sombre").contains("display"))
        #expect(ids("insurance").contains("pdf"))
        #expect(ids("assureur").contains("pdf"))
    }

    @Test func aSettingIsFoundByItsPageToo() {
        #expect(ids("export").isSuperset(of: ["csv", "pdf"]))
    }

    @Test func accountOnlySettingsAreHiddenWhenSignedOut() {
        #expect(ids("dossier", authenticated: true).contains("folders"))
        #expect(!ids("dossier", authenticated: false).contains("folders"))
        #expect(!ids("devise", authenticated: false).contains("currency"))
    }

    @Test func offlineLeadsToTheRightPageForPremiumAndNot() {
        let premium = SettingsSearchIndex.entries(isAuthenticated: true, isPremium: true).first { $0.id == "offline" }
        let free = SettingsSearchIndex.entries(isAuthenticated: true, isPremium: false).first { $0.id == "offline" }
        #expect(premium?.destination == .offline)
        #expect(free?.destination == .offlineLocked)
    }

    @Test func entryIdentifiersAreUnique() {
        let entries = SettingsSearchIndex.entries(isAuthenticated: true, isPremium: true)
        #expect(Set(entries.map(\.id)).count == entries.count)
    }
}
