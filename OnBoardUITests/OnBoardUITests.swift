//
//  OnBoardUITests.swift
//  OnBoardUITests
//
//  Created by Olli Tapaninen on 2026-09-15.
//

import XCTest

final class OnBoardUITests: XCTestCase {

    override func setUpWithError() throws {
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testNearbyStopsLoadFromMockNetwork() throws {
        // Launch the app with the mock network so the nearby view is served
        // canned stops instead of making real network requests.
        // `--skip-location-permission` pre-authorizes a fixed coordinate so the
        // location permission gate doesn't cover the nearby tab in the simulator
        // (where real CoreLocation permission can't be granted).
        let app = XCUIApplication()
        app.launchArguments = ["--mock-network", "--skip-location-permission", "--mock-storage"]
        app.launch()
        // Open home tab
        app/*@START_MENU_TOKEN@*/.images["location.fill"]/*[[".buttons[\"Nearby\"].images",".buttons",".images[\"location services\"]",".images[\"location.fill\"]"],[[[-1,3],[-1,2],[-1,1,1],[-1,0]],[[-1,3],[-1,2]]],[0]]@END_MENU_TOKEN@*/.firstMatch.tap()

        // The nearby tab is selected by default and renders the stop names
        // served by `MockTrafiklabService.defaultNearbyStopsJSON`.
        let firstStop = app.staticTexts["Medborgarplatsen"]
        let secondStop = app.staticTexts["Slussen"]

        XCTAssertTrue(firstStop.waitForExistence(timeout: 10),
                     "Expected the first mock stop to appear in the nearby list.")
        XCTAssertTrue(secondStop.exists,
                     "Expected the second mock stop to appear in the nearby list.")
    }

    @MainActor
    func testSavedTripAppearsInFavouritesFromMockStorage() throws {
        // Launch with the mock network and storage: `mockModelContainer()`
        // seeds one stop and one saved trip (Line 3 → Karolinska sjukhuset,
        // its end date 30 minutes out, so it reads as live), so the
        // Favourites tab shows the live trip above the stops.
        let app = XCUIApplication()
        app.launchArguments = ["--mock-network", "--skip-location-permission", "--mock-storage"]
        app.launch()

        // Open the Favourites tab.
        app.buttons["Favorites"].tap()

        // The live-trips section renders on top (the saved end date hasn't
        // passed), the saved trip's direction and line summary in its row,
        // followed by the stops section.
        let destination = app.staticTexts["Karolinska sjukhuset"]
        XCTAssertTrue(destination.waitForExistence(timeout: 10),
                     "Expected the saved trip's destination to appear in the live-trips section.")
        XCTAssertTrue(app.staticTexts["Line 3"].exists,
                     "Expected the saved trip's line summary to appear in the live-trips section.")
        XCTAssertTrue(app.staticTexts["Live trips"].exists,
                     "Expected the live-trips section header above the stops.")
        XCTAssertTrue(app.staticTexts["Medborgarplatsen"].waitForExistence(timeout: 10),
                     "Expected the seeded favourite stop to appear below the live trips.")
    }
}
