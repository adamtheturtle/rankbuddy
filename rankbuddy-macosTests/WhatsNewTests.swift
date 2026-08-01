//
//  WhatsNewTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing
import WhatsNewKit

/// The package owns show-once/version behavior; the app still supplies release content.
@MainActor
struct WhatsNewTests {
    @Test func `there is at least one highlight to show`() {
        #expect(WhatsNewContent.featureCount > 0)
    }

    @Test func `legacy dismissal migrates into WhatsNewKit and is retired`() throws {
        let suite = "whats-new-migration-test"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set("1.2.3", forKey: WhatsNewContent.legacyLastSeenKey)

        let store = WhatsNewContent.versionStore(defaults: defaults)

        #expect(store.hasPresented(WhatsNew.Version(stringLiteral: "1.2.3")))
        #expect(defaults.object(forKey: WhatsNewContent.legacyLastSeenKey) == nil)
        defaults.removePersistentDomain(forName: suite)
    }
}
