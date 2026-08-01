//
//  AppPresenceMonitorTests.swift
//  rankbuddy-macosTests
//

import AppKit
import Foundation
@testable import rankbuddy_macos
import Testing

@MainActor
struct AppPresenceMonitorTests {
    @Test func `reconcile applies a changed preference without window content`() throws {
        let suite = "app-presence-monitor-apply-test"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(AppPresence.menuBarOnly.rawValue, forKey: AppPresence.defaultsKey)
        var requestedPolicy: NSApplication.ActivationPolicy?
        let monitor = AppPresenceMonitor(
            defaults: defaults,
            currentPolicy: { .regular },
            setPolicy: {
                requestedPolicy = $0
                return true
            },
            activate: {}
        )

        let effective = monitor.reconcile()

        #expect(effective == .menuBarOnly)
        #expect(requestedPolicy == .accessory)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func `reconcile rolls back a rejected background change`() throws {
        let suite = "app-presence-monitor-reject-test"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(AppPresence.menuBarOnly.rawValue, forKey: AppPresence.defaultsKey)
        let monitor = AppPresenceMonitor(
            defaults: defaults,
            currentPolicy: { .regular },
            setPolicy: { _ in false },
            activate: {}
        )

        let effective = monitor.reconcile()

        #expect(effective == .both)
        #expect(AppPresence.current(defaults: defaults) == .both)
        defaults.removePersistentDomain(forName: suite)
    }
}
