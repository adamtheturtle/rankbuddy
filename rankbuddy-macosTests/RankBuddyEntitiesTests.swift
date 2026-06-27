//
//  RankBuddyEntitiesTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the App Entities / Spotlight routing (#24): the composite-id round-trip and
/// that opening an entity writes the same per-account selection key the lists restore from.
@MainActor
struct RankBuddyEntitiesTests {
    @Test func `the composite id encodes collection, account, and item`() {
        let entity = RankBuddyObjectEntity(collection: .questions, accountID: "acc1", itemID: "q42", title: "Two Sum")
        #expect(entity.id == "questions|acc1|q42")
        #expect(entity.title == "Two Sum")
    }

    @Test func `an entity round-trips through its id`() throws {
        let entity = try #require(RankBuddyObjectEntity(id: "interviews|acc9|i7", title: "Pairing"))
        #expect(entity.collection == .interviews)
        #expect(entity.accountID == "acc9")
        #expect(entity.itemID == "i7")
        #expect(entity.title == "Pairing")
    }

    @Test func `an item id containing a pipe is preserved`() throws {
        // maxSplits keeps any later pipes as part of the item id.
        let entity = try #require(RankBuddyObjectEntity(id: "tests|acc1|odd|id", title: "T"))
        #expect(entity.itemID == "odd|id")
    }

    @Test func `a malformed id does not produce an entity`() {
        #expect(RankBuddyObjectEntity(id: "garbage", title: "x") == nil)
        #expect(RankBuddyObjectEntity(id: "nope|acc1|i1", title: "x") == nil)
    }

    @Test func `opening an entity writes the section's restoration key`() {
        let key = "selection.tests.acctZ"
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.removeObject(forKey: "selectedSection")
        }

        RankBuddyDeepLink.open(collection: .tests, accountID: "acctZ", itemID: "t99")
        #expect(UserDefaults.standard.string(forKey: key) == "t99")
        #expect(UserDefaults.standard.string(forKey: "selectedSection") == "tests")
    }

    @Test func `the spotlight index name is shared by donation and clearing`() {
        // Donation (suggestedEntities) and deletion-on-removal must target the same index, or a
        // deleted account's items would linger (#24). Pin the name so the two can't drift apart.
        #expect(RankBuddySpotlightIndex.name == "RankBuddyObjects")
    }

    @Test func `clearing the spotlight index completes without throwing`() async {
        // Best-effort deletion: it must never throw into the account-removal path, even when
        // Spotlight is unavailable in the test environment.
        await RankBuddySpotlightIndex.clear()
    }
}
