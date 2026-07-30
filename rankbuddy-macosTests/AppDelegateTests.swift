//
//  AppDelegateTests.swift
//  rankbuddy-macosTests
//

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

    @Test func `dock items use the registered main window presenter`() {
        var presentations = 0
        let delegate = AppDelegate(showMainWindow: { presentations += 1 })
        guard let item = delegate.applicationDockMenu(.shared)?.items.first,
              let action = item.action
        else {
            Issue.record("Expected an actionable Dock menu item")
            return
        }

        NSApp.sendAction(action, to: item.target, from: item)

        #expect(presentations == 1)
    }
}
