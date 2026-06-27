import AppKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the Dock menu (#45): one item per sidebar section, in order.
@MainActor
struct AppDelegateTests {
    @Test func `the dock menu lists every section in order`() {
        let menu = AppDelegate().applicationDockMenu(.shared)
        let titles = menu?.items.map(\.title)
        #expect(titles == SidebarSection.allCases.map(\.title))
    }

    @Test func `each dock item carries its section raw value`() {
        let menu = AppDelegate().applicationDockMenu(.shared)
        let raws = menu?.items.compactMap { $0.representedObject as? String }
        #expect(raws == SidebarSection.allCases.map(\.rawValue))
    }
}
