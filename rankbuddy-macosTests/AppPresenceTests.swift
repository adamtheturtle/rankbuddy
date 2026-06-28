//
//  AppPresenceTests.swift
//  rankbuddy-macosTests
//

import AppKit
import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the app-presence setting (#66): which surfaces each option shows and the
/// activation policy it maps to.
@MainActor
struct AppPresenceTests {
    @Test func `both shows the dock and the menu bar`() {
        #expect(AppPresence.both.showsDockIcon)
        #expect(AppPresence.both.showsMenuBarIcon)
        #expect(AppPresence.both.activationPolicy == .regular)
    }

    @Test func `dock only hides the menu bar but keeps the dock icon`() {
        #expect(AppPresence.dockOnly.showsDockIcon)
        #expect(AppPresence.dockOnly.showsMenuBarIcon == false)
        #expect(AppPresence.dockOnly.activationPolicy == .regular)
    }

    @Test func `menu bar only runs as an accessory with no dock icon`() {
        #expect(AppPresence.menuBarOnly.showsDockIcon == false)
        #expect(AppPresence.menuBarOnly.showsMenuBarIcon)
        #expect(AppPresence.menuBarOnly.activationPolicy == .accessory)
    }

    @Test func `every option keeps at least one surface visible`() {
        // The picker can never make the app fully invisible.
        for option in AppPresence.allCases {
            #expect(option.showsDockIcon || option.showsMenuBarIcon)
        }
    }

    @Test func `current defaults to both for an unset or unknown value`() throws {
        let defaults = try #require(UserDefaults(suiteName: "app-presence-test"))
        defaults.removePersistentDomain(forName: "app-presence-test")
        #expect(AppPresence.current(defaults: defaults) == .both)

        defaults.set("menuBarOnly", forKey: AppPresence.defaultsKey)
        #expect(AppPresence.current(defaults: defaults) == .menuBarOnly)

        defaults.set("nonsense", forKey: AppPresence.defaultsKey)
        #expect(AppPresence.current(defaults: defaults) == .both)

        defaults.removePersistentDomain(forName: "app-presence-test")
    }
}
