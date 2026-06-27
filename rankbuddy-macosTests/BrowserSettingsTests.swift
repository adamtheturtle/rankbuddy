import AppKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the link-opening preferences (#63). Only the read-only LaunchServices queries
/// are exercised — `open(_:)` is a side effect (it would launch a browser) and isn't called.
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
}
