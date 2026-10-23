import Testing
@testable import Spinlog

/// Support affiché par la feuille d'écoute sur platine, d'après les formats Discogs.
struct PhysicalMediaTests {
    @Test func vinylFormatsStayVinyl() {
        #expect(PhysicalMedia.from(formatNames: ["Vinyl"]) == .vinyl)
    }

    @Test func compactDiscFormatsAreCD() {
        #expect(PhysicalMedia.from(formatNames: ["CD"]) == .cd)
        #expect(PhysicalMedia.from(formatNames: ["CDr"]) == .cd)
        #expect(PhysicalMedia.from(formatNames: ["SACD"]) == .cd)
        #expect(PhysicalMedia.from(formatNames: [" cd "]) == .cd)
    }

    /// Le premier support reconnu décide : un coffret de CD est un CD, un vinyle avec CD bonus un vinyle.
    @Test func theFirstRecognisedFormatWins() {
        #expect(PhysicalMedia.from(formatNames: ["Box Set", "CD"]) == .cd)
        #expect(PhysicalMedia.from(formatNames: ["Vinyl", "CD"]) == .vinyl)
        #expect(PhysicalMedia.from(formatNames: ["CD", "Vinyl"]) == .cd)
    }

    @Test func cassetteFormatIsACassette() {
        #expect(PhysicalMedia.from(formatNames: ["Cassette"]) == .cassette)
        #expect(PhysicalMedia.from(formatNames: ["Box Set", "Cassette"]) == .cassette)
        #expect(PhysicalMedia.from(formatNames: ["Cassette", "CD"]) == .cassette)
    }

    @Test func unknownOrMissingFormatsFallBackToVinyl() {
        #expect(PhysicalMedia.from(formatNames: []) == .vinyl)
        #expect(PhysicalMedia.from(formatNames: ["File"]) == .vinyl)
    }

    /// La coque reste lisible quelle que soit la pochette : presque blanche, presque noire ou grise.
    @Test func cassetteShellStaysReadableForAnyCover() {
        let white = CassetteView.shellHSB(hue: 0.1, saturation: 0.0, brightness: 1.0)
        #expect(white.top <= 0.92 && white.bottom < white.top)
        #expect(white.saturation >= 0.12)
        let black = CassetteView.shellHSB(hue: 0.6, saturation: 0.9, brightness: 0.02)
        #expect(black.bottom >= 0.38 * 0.62 - 0.0001)
        #expect(black.saturation <= 0.85)
        let vivid = CassetteView.shellHSB(hue: 0.0, saturation: 0.8, brightness: 0.7)
        #expect(vivid.top > vivid.bottom)
    }
}
