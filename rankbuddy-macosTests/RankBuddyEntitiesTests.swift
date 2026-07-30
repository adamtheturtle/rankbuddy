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

    @Test func `entity query reconstructs routes without network data`() async throws {
        let entities = try await RankBuddyObjectEntityQuery().entities(for: [
            "questions|acc1|q42",
            "invalid"
        ])

        #expect(entities.count == 1)
        #expect(entities.first?.collection == .questions)
        #expect(entities.first?.accountID == "acc1")
        #expect(entities.first?.itemID == "q42")
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

    @Test func `opening an entity selects its encoded account`() {
        let first = Account(label: "First", token: "t1")
        let target = Account(label: "Target", token: "t2")
        let store = AccountStore.rankBuddy(isTesting: true, seed: [first, target])
        store.showAllAccounts = true

        RankBuddyDeepLink.open(
            collection: .questions,
            accountID: target.id.uuidString,
            itemID: "q1",
            store: store
        )

        #expect(!store.showAllAccounts)
        #expect(store.currentAccountID == target.id)
    }

    @Test func `the selection key matches the deep-link router request`() {
        // The router lets an already-on-screen list reveal a same-section favourite without a
        // reload (#122). Its request key must equal the key the list restores from, or no list
        // would ever match it.
        RankBuddyDeepLink.open(collection: .questions, accountID: "acctQ", itemID: "q7")

        let key = RankBuddyDeepLink.selectionKey(collection: .questions, accountID: "acctQ")
        #expect(key == "selection.questions.acctQ")
        #expect(DeepLinkRouter.shared.request?.key == key)
        #expect(DeepLinkRouter.shared.request?.itemID == "q7")
    }

    @Test func `re-opening the same item posts a distinct request`() {
        // A fresh request identity per open means clicking the same favourite twice still
        // registers as a change the list reacts to (#122).
        RankBuddyDeepLink.open(collection: .tests, accountID: "acctR", itemID: "t1")
        let first = DeepLinkRouter.shared.request
        RankBuddyDeepLink.open(collection: .tests, accountID: "acctR", itemID: "t1")
        let second = DeepLinkRouter.shared.request

        #expect(first != second)
    }

    @Test func `the spotlight index name is shared by donation and clearing`() {
        // Donation (suggestedEntities) and deletion-on-removal must target the same index, or a
        // deleted account's items would linger (#24). Pin the name so the two can't drift apart.
        #expect(RankBuddySpotlightIndex.name == "RankBuddyObjects")
    }

    @Test func `spotlight entities carry an account deletion domain`() {
        let entity = RankBuddyObjectEntity(
            collection: .tests,
            accountID: "account-id",
            itemID: "test-id",
            title: "Test"
        )
        #expect(entity.attributeSet.domainIdentifier == "account-id")
    }

    @Test func `clearing the spotlight index completes without throwing`() async {
        // Best-effort deletion: it must never throw into the account-removal path, even when
        // Spotlight is unavailable in the test environment.
        await RankBuddySpotlightIndex.clear()
    }
}
