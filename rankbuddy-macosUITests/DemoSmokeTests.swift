//
//  DemoSmokeTests.swift
//  rankbuddy-macosUITests
//

import XCTest

final class DemoSmokeTests: XCTestCase {
    @MainActor
    func testDemoLaunchesAndNavigatesPrimarySections() {
        let app = XCUIApplication()
        app.launchEnvironment["RANKBUDDY_DEMO"] = "1"
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        for section in ["Tests", "Questions", "Interviews", "People", "Teams"] {
            let destination = app.buttons[section]
            XCTAssertTrue(destination.waitForExistence(timeout: 10), "\(section) destination is missing")
            destination.click()
            XCTAssertTrue(app.staticTexts[section].waitForExistence(timeout: 10), "\(section) screen did not load")
        }
    }
}
