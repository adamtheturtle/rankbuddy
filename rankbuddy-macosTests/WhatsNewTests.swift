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

    @Test func `downgrades and older builds do not present as new releases`() {
        #expect(!WhatsNew.shouldShow(currentVersion: "1.9", currentBuild: "9", lastSeenRelease: "2.0|1"))
        #expect(!WhatsNew.shouldShow(currentVersion: "2.0", currentBuild: "4", lastSeenRelease: "2.0|5"))
        #expect(WhatsNew.shouldShow(currentVersion: "2.0", currentBuild: "6", lastSeenRelease: "2.0|5"))
    }

    @Test func `version comparison is numeric and migrates a legacy version-only value`() {
        #expect(WhatsNew.shouldShow(currentVersion: "1.10", currentBuild: "1", lastSeenRelease: "1.9|99"))
        #expect(!WhatsNew.shouldShow(currentVersion: "1.9", currentBuild: "99", lastSeenRelease: "1.10|1"))
        #expect(WhatsNew.shouldShow(currentVersion: "2.0", currentBuild: "1", lastSeenRelease: "2.0"))
    }

    @Test func `there is at least one highlight to show`() {
        #expect(!WhatsNew.highlights.isEmpty)
    }
}
