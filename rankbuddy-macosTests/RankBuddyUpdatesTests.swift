//
//  RankBuddyUpdatesTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

/// Coverage for the Sparkle feed gate (#11): the updater (and its menu item) only activates
/// when a non-empty appcast feed URL is configured.
@MainActor
struct RankBuddyUpdatesTests {
    @Test func `a configured feed url enables updates`() {
        #expect(RankBuddyUpdates.feedConfigured("https://example.com/appcast.xml"))
    }

    @Test func `a missing or blank feed url keeps updates off`() {
        #expect(!RankBuddyUpdates.feedConfigured(nil))
        #expect(!RankBuddyUpdates.feedConfigured(""))
        #expect(!RankBuddyUpdates.feedConfigured("   "))
        #expect(!RankBuddyUpdates.feedConfigured("\n\r\n"))
        #expect(!RankBuddyUpdates.feedConfigured(42))
    }
}
