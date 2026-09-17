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

        // The nearby tab is selected by default and renders the stop names
        // served by `MockTrafiklabService.defaultNearbyStops`.
        let firstStop = app.staticTexts["Medborgarplatsen"]
        let secondStop = app.staticTexts["Slussen"]

        XCTAssertTrue(firstStop.waitForExistence(timeout: 10),
                     "Expected the first mock stop to appear in the nearby list.")
        XCTAssertTrue(secondStop.exists,
                     "Expected the second mock stop to appear in the nearby list.")
    }
}
