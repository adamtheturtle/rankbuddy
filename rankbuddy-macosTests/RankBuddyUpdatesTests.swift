//
//  RankBuddyUpdatesTests.swift
//  rankbuddy-macosTests
//

import Foundation
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

    @Test func `only a valid HTTPS feed with a host enables updates`() {
        #expect(RankBuddyUpdates.feedConfigured("  HTTPS://updates.example.com/appcast.xml\n"))
        #expect(!RankBuddyUpdates.feedConfigured("http://example.com/appcast.xml"))
        #expect(!RankBuddyUpdates.feedConfigured("file:///tmp/appcast.xml"))
        #expect(!RankBuddyUpdates.feedConfigured("/relative/appcast.xml"))
        #expect(!RankBuddyUpdates.feedConfigured("https:///appcast.xml"))
        #expect(!RankBuddyUpdates.feedConfigured("not a url"))
    }

    @Test func `only a base64 encoded Ed25519 public key enables update verification`() {
        let validKey = Data(repeating: 0xA5, count: 32).base64EncodedString()

        #expect(RankBuddyUpdates.signingKeyConfigured(" \n\(validKey)\n"))
        #expect(!RankBuddyUpdates.signingKeyConfigured(nil))
        #expect(!RankBuddyUpdates.signingKeyConfigured(""))
        #expect(!RankBuddyUpdates.signingKeyConfigured("not-base64"))
        #expect(!RankBuddyUpdates.signingKeyConfigured(Data(repeating: 1, count: 31).base64EncodedString()))
        #expect(!RankBuddyUpdates.signingKeyConfigured(42))
    }
}
