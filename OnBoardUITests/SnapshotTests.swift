//
//  SnapshotTests.swift
//  OnBoardUITests
//
//  Captures App Store screenshots for fastlane snapshot. Runs under the
//  `--mock-network`, `--skip-location-permission`, and `--mock-storage`
//  harness, so the shots are deterministic and need no real Trafiklab keys.
//  `setupSnapshot` pins the app's language and locale per run (fastlane
//  re-runs this test once per language in the Snapfile's `languages` list),
//  and tab navigation uses the accessibility identifiers set on the tab bar
//  buttons in `MainView`, so it works in every language.
//

import XCTest

final class SnapshotTests: XCTestCase {

    override func setUpWithError() throws {
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {}

    /// Resolves a tab bar button by its accessibility identifier (set in
    /// `MainView` on each `Tab`), so navigation is locale-proof. On iPad the
    /// floating tab bar exposes each item as nested buttons with the same
    /// identifier, and tapping an ambiguous query fails at once. Always
    /// resolve to a single element.
    @MainActor
    private func tabButton(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let inTabBar = app.tabBars.buttons[identifier].firstMatch
        if inTabBar.waitForExistence(timeout: 10) { return inTabBar }
        let fallback = app.buttons[identifier].firstMatch
        XCTAssertTrue(
            fallback.waitForExistence(timeout: 10),
            "Expected the \(identifier) tab button to appear."
        )
        return fallback
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
        let firstStop = app.staticTexts["Medborgarplatsen"].firstMatch
        XCTAssertTrue(firstStop.waitForExistence(timeout: 10),
                      "Expected the first mock stop to appear in the nearby list.")
        snapshot("01_Nearby")

        // Stop board: tap the first stop and wait for its mock departures
        // (Line 3 towards Karolinska sjukhuset) to render. The tab bar is
        // hidden on the stop board, so afterwards press the back button to
        // return to Nearby before switching tabs.
        firstStop.tap()
        let departureDestination = app.staticTexts["Karolinska sjukhuset"].firstMatch
        XCTAssertTrue(departureDestination.waitForExistence(timeout: 10),
                      "Expected the mock departures to appear on the stop board.")
        snapshot("02_StopBoard")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(firstStop.waitForExistence(timeout: 10),
                      "Expected to return to the nearby list after pressing back.")

        // Search tab: type a query so matching stop groups are listed.
        tabButton(app, "Tab.Search").tap()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10),
                      "Expected the search field to appear.")
        searchField.tap()
        searchField.typeText("Slu")
        let slussen = app.staticTexts["Slussen"].firstMatch
        XCTAssertTrue(slussen.waitForExistence(timeout: 10),
                      "Expected the search results to include Slussen.")
        snapshot("03_Search")

        // The tab bar is hidden in pushed views, so open the Slussen result
        // (which also dismisses the keyboard), then press the back button to
        // return to Search before switching tabs.
        slussen.tap()
        XCTAssertTrue(app.staticTexts["Ropsten"].firstMatch.waitForExistence(timeout: 10),
                      "Expected the mock departures to appear on the Slussen board.")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 10),
                      "Expected to return to Search after pressing back.")
        // The tab bar minimizes while the keyboard is up, so dismiss it by
        // sending a return-key press (locale-proof) before switching tabs.
        if app.keyboards.firstMatch.exists {
            app.typeText("\n")
        }

        // Favourites tab: `--mock-storage` seeds one live trip (Line 3 to
        // Karolinska sjukhuset) above the saved stops.
        tabButton(app, "Tab.Favorites").tap()
        XCTAssertTrue(app.staticTexts["Karolinska sjukhuset"].firstMatch.waitForExistence(timeout: 10),
                      "Expected the seeded live trip to appear in Favourites.")
        snapshot("04_Favorites")

        // About tab: the app's attribution screen.
        tabButton(app, "Tab.About").tap()
        XCTAssertTrue(app.staticTexts["Olli Tapaninen"].firstMatch.waitForExistence(timeout: 10),
                      "Expected the creator name on the About screen.")
        snapshot("05_About")
    }
}
