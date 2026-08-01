//
//  PreferenceSyncTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

@MainActor
struct PreferenceSyncTests {
    @Test func `snapshot contains only the explicit safe allowlist`() throws {
        let suiteName = "preference-sync-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("dark", forKey: AppAppearance.defaultsKey)
        defaults.set(true, forKey: LivenessSettings.notifyKey)
        defaults.set(true, forKey: MCPServerSettings.allowWritesKey)
        defaults.set("secret", forKey: "accounts")

        let snapshot = PreferenceSyncCoordinator.snapshot(defaults: defaults)

        #expect(snapshot[AppAppearance.defaultsKey] == .string("dark"))
        #expect(snapshot[LivenessSettings.notifyKey] == .bool(true))
        #expect(snapshot[MCPServerSettings.allowWritesKey] == nil)
        #expect(snapshot["accounts"] == nil)
    }

    @Test func `applying a remote snapshot propagates values and deletions`() throws {
        let suiteName = "preference-sync-apply-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: MenuBarPreferences.activeOnlyKey)
        defaults.set(true, forKey: MCPServerSettings.allowWritesKey)

        PreferenceSyncCoordinator.apply(
            [AppAppearance.defaultsKey: .string("light")],
            defaults: defaults
        )

        #expect(defaults.string(forKey: AppAppearance.defaultsKey) == "light")
        #expect(defaults.object(forKey: MenuBarPreferences.activeOnlyKey) == nil)
        #expect(defaults.bool(forKey: MCPServerSettings.allowWritesKey))
    }
}
