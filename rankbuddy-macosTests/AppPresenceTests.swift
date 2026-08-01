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

    @Test func `menu extra insertion writes back without hiding every surface`() {
        #expect(AppPresence.dockOnly.settingMenuBarInserted(true) == .both)
        #expect(AppPresence.both.settingMenuBarInserted(false) == .dockOnly)
        #expect(AppPresence.menuBarOnly.settingMenuBarInserted(false) == .dockOnly)
        #expect(AppPresence.menuBarOnly.settingMenuBarInserted(true) == .menuBarOnly)
    }

    @Test func `dock visibility reports rejection and does not activate`() {
        var requestedPolicy: NSApplication.ActivationPolicy?
        var didActivate = false

        let applied = AppPresence.dockOnly.applyDockVisibility(
            currentPolicy: { .accessory },
            setPolicy: {
                requestedPolicy = $0
                return false
            },
            activate: { didActivate = true }
        )

        #expect(!applied)
        #expect(requestedPolicy == .regular)
        #expect(!didActivate)
    }

    @Test func `successful dock restoration activates only after policy acceptance`() {
        var didActivate = false
        let applied = AppPresence.both.applyDockVisibility(
            currentPolicy: { .accessory },
            setPolicy: { $0 == .regular },
            activate: { didActivate = true }
        )

        #expect(applied)
        #expect(didActivate)
        #expect(AppPresence.dockOnly.matchingActualPolicy(.regular) == .dockOnly)
        #expect(AppPresence.both.matchingActualPolicy(.regular) == .both)
        #expect(AppPresence.dockOnly.matchingActualPolicy(.accessory) == .menuBarOnly)
    }

    @Test func `startup reconciliation persists the policy that remains after rejection`() throws {
        let suite = "app-presence-reconciliation-test"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(AppPresence.menuBarOnly.rawValue, forKey: AppPresence.defaultsKey)

        let effective = AppPresence.menuBarOnly.applyDockVisibilityReconciling(
            defaults: defaults,
            currentPolicy: { .regular },
            setPolicy: { _ in false },
            activate: {}
        )

        #expect(effective == .both)
        #expect(AppPresence.current(defaults: defaults) == .both)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func `startup reconciliation preserves an accepted preference`() throws {
        let suite = "app-presence-accepted-test"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(AppPresence.menuBarOnly.rawValue, forKey: AppPresence.defaultsKey)

        let effective = AppPresence.menuBarOnly.applyDockVisibilityReconciling(
            defaults: defaults,
            currentPolicy: { .accessory },
            setPolicy: { _ in true },
            activate: {}
        )

        #expect(effective == .menuBarOnly)
        #expect(AppPresence.current(defaults: defaults) == .menuBarOnly)
        defaults.removePersistentDomain(forName: suite)
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
