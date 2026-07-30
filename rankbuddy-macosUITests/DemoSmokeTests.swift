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
    func testCaptureLightMarketingScreenshots() {
        captureScreenshots(appearance: "Light")
    }

    @MainActor
    func testCaptureDarkMarketingScreenshots() {
        captureScreenshots(appearance: "Dark")
    }

    @MainActor
    private func captureScreenshots(appearance: String) {
        let app = launchDemo(appearance: appearance)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        for section in sections {
            navigate(to: section, in: app)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "RankBuddy-\(appearance)-\(section)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    private func launchDemo(appearance: String = "Light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RANKBUDDY_DEMO"] = "1"
        app.launchArguments += ["-AppleInterfaceStyle", appearance]
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
