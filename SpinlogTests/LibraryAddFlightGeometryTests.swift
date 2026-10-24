import CoreGraphics
import Testing
@testable import Spinlog

struct LibraryAddFlightGeometryTests {
    private let screen = CGSize(width: 393, height: 852)

    @Test func collectionLandsLeftOfWantlistInTheBottomBar() {
        let collection = LibraryAddFlightGeometry.landingPoint(for: .collection, screen: screen, bottomInset: 34)
        let wantlist = LibraryAddFlightGeometry.landingPoint(for: .wantlist, screen: screen, bottomInset: 34)
        #expect(collection.x < wantlist.x)
        #expect(collection.y == wantlist.y)
        #expect(collection.y > screen.height - 100)
        #expect(wantlist.x < screen.width / 2)
    }

    @Test func flightStartsInTheMiddleOfTheScreen() {
        let start = LibraryAddFlightGeometry.startPoint(screen: screen)
        #expect(start.x == screen.width / 2)
        #expect(start.y < screen.height / 2)
    }
}

/// Choix du bouton d'onglet visé : mesures relevées sur iPhone 17 (iOS 27, écran 402 × 874).
struct TabBarIconSelectionTests {
    private let expanded: [CGRect] = [
        CGRect(x: 25, y: 795, width: 90.5, height: 54),
        CGRect(x: 95.5, y: 795, width: 81.4, height: 54),
        CGRect(x: 156.9, y: 795, width: 81.4, height: 54),
        CGRect(x: 218.3, y: 795, width: 85.2, height: 54),
        CGRect(x: 283.5, y: 795, width: 93.5, height: 54)
    ]
    /// Barre réduite : l'onglet actif à gauche, la recherche à droite, 48 pt chacun.
    private let reduced: [CGRect] = [
        CGRect(x: 28, y: 798, width: 48, height: 48),
        CGRect(x: 326, y: 798, width: 48, height: 48)
    ]

    @Test func expandedBarTargetsTheCollectionAndWantlistButtons() {
        #expect(TabBarIconSelection.landingFrame(for: .collection, among: expanded) == expanded[0])
        #expect(TabBarIconSelection.landingFrame(for: .wantlist, among: expanded) == expanded[1])
    }

    /// Régression : en barre réduite, le « bouton n° 1 » de la Wantlist était la loupe.
    @Test func reducedBarNeverTargetsTheSearchPill() {
        #expect(TabBarIconSelection.landingFrame(for: .collection, among: reduced) == reduced[0])
        #expect(TabBarIconSelection.landingFrame(for: .wantlist, among: reduced) == reduced[0])
    }

    @Test func reducedBarIgnoresWideButtonsThatStayInTheHierarchy() {
        let frames = expanded + reduced
        #expect(TabBarIconSelection.isReduced(frames))
        #expect(TabBarIconSelection.landingFrame(for: .wantlist, among: frames) == reduced[0])
    }

    @Test func framesAreSortedBeforeChoosing() {
        let shuffled = [expanded[2], expanded[0], expanded[1]]
        #expect(TabBarIconSelection.landingFrame(for: .wantlist, among: shuffled) == expanded[1])
    }

    @Test func noButtonMeansNoTarget() {
        #expect(TabBarIconSelection.landingFrame(for: .collection, among: []) == nil)
        #expect(TabBarIconSelection.landingFrame(for: .wantlist, among: [expanded[0]]) == nil)
    }
}

/// Mesures du 24 octobre : la barre déployée contient DEUX jeux identiques des 5 boutons
/// (contenu normal et contenu sélectionné), et les boutons s'appellent `_UITabButton`.
struct TabBarIconDuplicateTests {
    private let expanded: [CGRect] = [
        CGRect(x: 25, y: 795, width: 90.4931506849315, height: 54),
        CGRect(x: 95.49315068493149, y: 795, width: 81.39726027397262, height: 54),
        CGRect(x: 156.8904109589041, y: 795, width: 81.39726027397262, height: 54),
        CGRect(x: 218.28767123287673, y: 795, width: 85.18721461187215, height: 54),
        CGRect(x: 283.4748858447489, y: 795, width: 93.52511415525112, height: 54)
    ]

    @Test func duplicateButtonSetsAreCollapsed() {
        let doubled = expanded + expanded
        #expect(TabBarIconSelection.uniqueFrames(doubled).count == 5)
    }

    /// Régression : sans dédoublonnage, « le bouton n° 1 » (Wantlist) était un doublon de la Collection.
    @Test func wantlistIsNotADuplicateOfTheCollection() {
        let doubled = (expanded + expanded).sorted { $0.minX < $1.minX }
        #expect(TabBarIconSelection.landingFrame(for: .collection, among: doubled) == expanded[0])
        #expect(TabBarIconSelection.landingFrame(for: .wantlist, among: doubled) == expanded[1])
    }

    @Test func nearlyIdenticalFramesCountOnce() {
        let nudged = expanded[0].offsetBy(dx: 0.1, dy: 0)
        #expect(TabBarIconSelection.uniqueFrames([expanded[0], nudged]).count == 1)
    }
}
