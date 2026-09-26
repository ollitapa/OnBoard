//
//  SnapshotTests.swift
//  OnBoardUITests
//
//  Captures App Store screenshots for fastlane snapshot. Runs under the
//  `--mock-network`, `--skip-location-permission`, and `--mock-storage`
//  harness, so the shots are deterministic and need no real Trafiklab keys.
//  `setupSnapshot` pins the app's language and locale per run (fastlane
//  re-runs this test once per language in the Snapfile's `languages` list),
//  and tab navigation switches on that language so it works everywhere.
//

import XCTest

final class SnapshotTests: XCTestCase {

    override func setUpWithError() throws {
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {}

    /// The tab-bar labels per language, matching `Localizable.xcstrings`
    /// (`Tab.nearby`, `Tab.favorites`, `Tab.search`, `Tab.about`). Derived
    /// from `Snapshot.deviceLanguage`, which `setupSnapshot` reads from the
    /// language file fastlane writes for the current run.
    @MainActor
    private var labels: (nearby: String, favorites: String, search: String, about: String) {
        switch Snapshot.deviceLanguage {
        case let lang where lang.hasPrefix("sv"):
            return ("Nära dig", "Favoriter", "Sök", "Om appen")
        case let lang where lang.hasPrefix("fi"):
            return ("Lähistöllä", "Suosikit", "Haku", "Tietoja")
        default:
            return ("Nearby", "Favorites", "Search", "About")
        }
    }

    /// Captures the main screens: Nearby, a stop's departure board, Search
    /// mid-query, Favourites with the seeded live trip and stops, and About.
    @MainActor
    func testCaptureScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mock-network", "--skip-location-permission", "--mock-storage"]
        setupSnapshot(app)
        app.launch()

        // Nearby tab (selected by default): the mock's first stop appears.
        let firstStop = app.staticTexts["Medborgarplatsen"]
        XCTAssertTrue(firstStop.waitForExistence(timeout: 10),
                      "Expected the first mock stop to appear in the nearby list.")
        snapshot("01_Nearby")

        // Stop board: tap the first stop and wait for its mock departures
        // (Line 3 towards Karolinska sjukhuset) to render.
        firstStop.tap()
        let departureDestination = app.staticTexts["Karolinska sjukhuset"]
        XCTAssertTrue(departureDestination.waitForExistence(timeout: 10),
                      "Expected the mock departures to appear on the stop board.")
        snapshot("02_StopBoard")

        // Search tab: type a query so matching stop groups are listed.
        app.buttons[labels.search].tap()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10),
                      "Expected the search field to appear.")
        searchField.tap()
        searchField.typeText("Slu")
        XCTAssertTrue(app.staticTexts["Slussen"].waitForExistence(timeout: 10),
                      "Expected the search results to include Slussen.")
        snapshot("03_Search")

        // Favourites tab: `--mock-storage` seeds one live trip (Line 3 to
        // Karolinska sjukhuset) above the saved stops.
        app.buttons[labels.favorites].tap()
        XCTAssertTrue(app.staticTexts["Karolinska sjukhuset"].waitForExistence(timeout: 10),
                      "Expected the seeded live trip to appear in Favourites.")
        snapshot("04_Favorites")

        // About tab: the app's attribution screen.
        app.buttons[labels.about].tap()
        XCTAssertTrue(app.staticTexts["Olli Tapaninen"].waitForExistence(timeout: 10),
                      "Expected the creator name on the About screen.")
        snapshot("05_About")
    }
}
