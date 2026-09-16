//
//  OnBoardUITests.swift
//  OnBoardUITests
//
//  Created by Olli Tapaninen on 2026-09-15.
//

import XCTest

final class OnBoardUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testNearbyStopsLoadFromMockNetwork() throws {
        // Launch the app with the mock network so the nearby view is served
        // canned stops instead of making real network requests. The
        // argument matches `mockNetworkLaunchArgument` in the app target.
        let app = XCUIApplication()
        app.launchArguments = ["--mock-network"]
        app.launch()

        // The nearby tab is selected by default and renders the stop names.
        let centralStation = app.staticTexts["Central Station"]
        let marketSquare = app.staticTexts["Market Square"]

        XCTAssertTrue(centralStation.waitForExistence(timeout: 10),
                     "Expected the first mock stop to appear in the nearby list.")
        XCTAssertTrue(marketSquare.exists,
                     "Expected the second mock stop to appear in the nearby list.")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
