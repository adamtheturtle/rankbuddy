//
//  BrowserSettingsTests.swift
//  rankbuddy-macosTests
//

import AppKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the link-opening preferences (#63). Only the read-only LaunchServices queries
/// are exercised — `open(_:)` is a side effect (it would launch a browser) and isn't called.
@MainActor
struct BrowserSettingsTests {
    @Test func `at least one browser is installed and resolves a bundle id`() {
        let browsers = BrowserSettings.installedBrowsers()
        // Every macOS has Safari registered for http(s).
        #expect(!browsers.isEmpty)
        #expect(browsers.allSatisfy { !$0.bundleID.isEmpty && !$0.name.isEmpty })
    }

    @Test func `the browser list is de-duplicated by bundle id`() {
        let ids = BrowserSettings.installedBrowsers().map(\.bundleID)
        #expect(Set(ids).count == ids.count)
    }

    @Test func `the system default browser name resolves`() {
        #expect(BrowserSettings.systemDefaultBrowserName() != nil)
    }

    @Test func `web URLs are openable`() throws {
        #expect(try BrowserSettings.isOpenableWebURL(#require(URL(string: "https://www.hackerrank.com/work/tests"))))
        #expect(try BrowserSettings.isOpenableWebURL(#require(URL(string: "http://localhost:8080/report"))))
    }

    @Test func `non-web URLs are refused`() throws {
        #expect(try !BrowserSettings.isOpenableWebURL(#require(URL(string: "file:///etc/passwd"))))
        #expect(try !BrowserSettings.isOpenableWebURL(#require(URL(string: "rankbuddy://tests/123"))))
        #expect(try !BrowserSettings.isOpenableWebURL(#require(URL(string: "ftp://example.com/report"))))
    }

    @Test func `hostless web URLs are refused`() throws {
        #expect(try !BrowserSettings.isOpenableWebURL(#require(URL(string: "https:///report"))))
    }
}
