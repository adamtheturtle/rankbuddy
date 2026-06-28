//
//  WhatsNewTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

/// Coverage for the "What's New" show-once decision (#47).
@MainActor
struct WhatsNewTests {
    @Test func `it shows for a never-seen or older version`() {
        #expect(WhatsNew.shouldShow(currentVersion: "1.1", lastSeenVersion: ""))
        #expect(WhatsNew.shouldShow(currentVersion: "1.1", lastSeenVersion: "1.0"))
    }

    @Test func `it does not show again once this version was seen`() {
        #expect(!WhatsNew.shouldShow(currentVersion: "1.1", lastSeenVersion: "1.1"))
    }

    @Test func `there is at least one highlight to show`() {
        #expect(!WhatsNew.highlights.isEmpty)
    }
}
