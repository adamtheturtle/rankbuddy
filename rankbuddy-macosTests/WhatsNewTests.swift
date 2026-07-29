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
        #expect(WhatsNew.shouldShow(currentVersion: "1.1", currentBuild: "1", lastSeenRelease: ""))
        #expect(WhatsNew.shouldShow(currentVersion: "1.1", currentBuild: "1", lastSeenRelease: "1.0|9"))
    }

    @Test func `it does not show again once this version and build were seen`() {
        #expect(!WhatsNew.shouldShow(currentVersion: "1.1", currentBuild: "2", lastSeenRelease: "1.1|2"))
    }

    @Test func `a new build can show corrected notes within the same marketing version`() {
        #expect(WhatsNew.shouldShow(currentVersion: "1.1", currentBuild: "3", lastSeenRelease: "1.1|2"))
    }

    @Test func `there is at least one highlight to show`() {
        #expect(!WhatsNew.highlights.isEmpty)
    }
}
