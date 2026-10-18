import XCTest

/// Parcours clés de l'app, joués sur la collection de démo : données fixes, aucun compte Discogs
/// ni écriture vers Discogs. L'app est lancée avec un argument réservé aux tests (voir
/// `UITestLaunchOptions`, Debug uniquement) qui saute le paywall de lancement.
/// Les fiches release interrogent le vrai catalogue Discogs : le Simulateur doit avoir du réseau.
@MainActor
final class DemoModeUITests: XCTestCase {
    private var app: XCUIApplication!

    // Préparation faite ici plutôt que dans `setUpWithError` : cette méthode héritée n'est pas
    // isolée sur l'acteur principal, contrairement à `XCUIApplication`.
    private func launch(_ argument: String) {
        continueAfterFailure = false
        app = XCUIApplication()
        // Libellés français, quelle que soit la langue du Simulateur.
        app.launchArguments += ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR", argument]
        app.launch()
    }

    private func launchInDemo() { launch("-uiTestDemo") }

    /// Premier disque affiché, quel que soit le mode (Liste, Mosaïque ou Carrousel).
    private var firstLibraryItem: XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'libraryItem-'"))
            .firstMatch
    }

    private func openTab(_ title: String) {
        let tab = app.tabBars.buttons[title]
        // La barre d'onglets se réduit quand on fait défiler vers le bas (`tabBarMinimizeBehavior`) :
        // remonter l'écran la fait réapparaître en entier.
        var swipes = 0
        while !tab.waitForExistence(timeout: 2) && swipes < 4 {
            app.swipeDown()
            swipes += 1
        }
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "onglet \(title) introuvable")
        tab.tap()
    }

    /// Fait défiler l'écran courant jusqu'à ce que l'élément apparaisse (Réglages est long).
    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 10) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }

    @MainActor
    func testLoginScreenOffersDemoAndOpensSampleCollection() {
        launch("-uiTestSignedOut")
        let demoButton = app.buttons["Explorer avec une collection de démo"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 10))

        demoButton.tap()

        XCTAssertTrue(firstLibraryItem.waitForExistence(timeout: 15), "la collection de démo ne s'affiche pas")
    }

    @MainActor
    func testCollectionAndWantlistShowSampleRecords() {
        launchInDemo()
        XCTAssertTrue(firstLibraryItem.waitForExistence(timeout: 15), "collection vide")

        openTab("Wantlist")

        XCTAssertTrue(firstLibraryItem.waitForExistence(timeout: 15), "wantlist vide")
    }

    @MainActor
    func testStatsTabOpensOnSampleData() {
        launchInDemo()
        XCTAssertTrue(firstLibraryItem.waitForExistence(timeout: 15))

        openTab("Stats")

        XCTAssertTrue(app.staticTexts["Statistiques"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testAddingToWantlistIsBlockedWithDemoMessage() {
        launchInDemo()
        let record = firstLibraryItem
        XCTAssertTrue(record.waitForExistence(timeout: 15))
        record.tap()

        // La fiche se charge depuis le catalogue Discogs (réseau).
        let wantlistButton = app.buttons["releaseWantlistButton"]
        scrollTo(wantlistButton, maxSwipes: 3)
        XCTAssertTrue(wantlistButton.waitForExistence(timeout: 20), "fiche release non chargée")
        wantlistButton.tap()

        let alert = app.alerts["Mode démo"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "aucun message de démo")
        alert.buttons.firstMatch.tap()
        XCTAssertFalse(alert.exists)
    }

    @MainActor
    func testExitingDemoReturnsToLoginScreen() {
        launchInDemo()
        XCTAssertTrue(firstLibraryItem.waitForExistence(timeout: 15))

        openTab("Réglages")
        let exitButton = app.buttons["Quitter le mode démo"]
        scrollTo(exitButton)
        XCTAssertTrue(exitButton.waitForExistence(timeout: 5))
        exitButton.tap()

        openTab("Collection")
        XCTAssertTrue(app.buttons["Explorer avec une collection de démo"].waitForExistence(timeout: 10))
    }
}
