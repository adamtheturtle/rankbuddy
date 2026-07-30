//
//  DemoSmokeTests.swift
//  rankbuddy-macosUITests
//

import XCTest

final class DemoSmokeTests: XCTestCase {
    private let sections = ["Tests", "Questions", "Interviews", "People", "Teams"]

    @MainActor
    func testDemoLaunchesAndNavigatesPrimarySections() {
        let app = launchDemo()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        for section in sections {
            navigate(to: section, in: app)
        }
    }

    @MainActor
    func testCaptureMarketingScreenshots() {
        let app = launchDemo()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        for section in sections {
            navigate(to: section, in: app)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "RankBuddy-\(section)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    private func launchDemo() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RANKBUDDY_DEMO"] = "1"
        app.launchArguments += ["-AppleInterfaceStyle", "Light"]
        app.launch()
        return app
    }

    @MainActor
    private func navigate(to section: String, in app: XCUIApplication) {
        let destination = app.buttons[section]
        XCTAssertTrue(destination.waitForExistence(timeout: 10), "\(section) destination is missing")
        destination.click()
        XCTAssertTrue(app.staticTexts[section].waitForExistence(timeout: 10), "\(section) screen did not load")
    }
}
