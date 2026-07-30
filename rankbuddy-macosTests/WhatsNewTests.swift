//
//  WhatsNewTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

/// The package owns show-once/version behavior; the app still supplies release content.
@MainActor
struct WhatsNewTests {
    @Test func `there is at least one highlight to show`() {
        #expect(WhatsNewContent.featureCount > 0)
    }
}
