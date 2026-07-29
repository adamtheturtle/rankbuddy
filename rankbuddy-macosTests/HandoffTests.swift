//
//  HandoffTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

struct HandoffTests {
    private let base = URL(string: "https://www.hackerrank.com") ?? URL(fileURLWithPath: "/")

    @Test func `web url uses the x-collection-id shape`() {
        let url = RankBuddyUserActivity.webURL(base: base, collection: .interviews, itemID: "i1")
        #expect(url?.absoluteString == "https://www.hackerrank.com/x/interviews/i1")
    }

    @Test func `web url honours a regional base host`() {
        let regional = URL(string: "https://example.hackerrank.com") ?? base
        let url = RankBuddyUserActivity.webURL(base: regional, collection: .tests, itemID: "t9")
        #expect(url?.absoluteString == "https://example.hackerrank.com/x/tests/t9")
    }

    @Test func `configure marks the activity eligible and carries the routing info`() {
        let activity = NSUserActivity(activityType: RankBuddyUserActivity.activityType)
        let webURL = RankBuddyUserActivity.webURL(base: base, collection: .tests, itemID: "t1")
        RankBuddyUserActivity.configure(
            activity,
            ref: .init(collection: .tests, accountID: "acc", itemID: "t1"),
            title: "Backend Screen",
            webURL: webURL
        )

        #expect(activity.title == "Backend Screen")
        #expect(activity.isEligibleForHandoff)
        #expect(activity.isEligibleForSearch)
        #expect(activity.webpageURL == webURL)
        #expect(activity.userInfo?[RankBuddyUserActivity.Key.collection] as? String == "tests")
        #expect(activity.userInfo?[RankBuddyUserActivity.Key.accountID] as? String == "acc")
        #expect(activity.userInfo?[RankBuddyUserActivity.Key.itemID] as? String == "t1")
    }

    @Test func `target round-trips through the userInfo a configure writes`() {
        let activity = NSUserActivity(activityType: RankBuddyUserActivity.activityType)
        RankBuddyUserActivity.configure(
            activity,
            ref: .init(collection: .questions, accountID: "acc", itemID: "q7"),
            title: "Two Sum",
            webURL: nil
        )

        let target = RankBuddyUserActivity.target(userInfo: activity.userInfo)
        #expect(target?.collection == .questions)
        #expect(target?.accountID == "acc")
        #expect(target?.itemID == "q7")
    }

    @Test func `target rejects a missing, foreign, or empty activity`() {
        #expect(RankBuddyUserActivity.target(userInfo: nil) == nil)
        #expect(RankBuddyUserActivity.target(userInfo: ["unrelated": "value"]) == nil)
        #expect(RankBuddyUserActivity.target(userInfo: [
            RankBuddyUserActivity.Key.collection: "tests",
            RankBuddyUserActivity.Key.accountID: "",
            RankBuddyUserActivity.Key.itemID: "t1"
        ]) == nil)
        #expect(RankBuddyUserActivity.target(userInfo: [
            RankBuddyUserActivity.Key.collection: "not-a-collection",
            RankBuddyUserActivity.Key.accountID: "acc",
            RankBuddyUserActivity.Key.itemID: "t1"
        ]) == nil)
    }

    @Test func `browser fallback accepts only HTTP HackerRank origins`() {
        let trustedHTTPS = URL(string: "https://www.hackerrank.com/x/tests/t1") ?? base
        let trustedHTTP = URL(string: "http://eu.hackerrank.com/x/tests/t1") ?? base
        let localFile = URL(string: "file:///tmp/item") ?? base
        let customScheme = URL(string: "rankbuddy://tests/t1") ?? base
        let deceptiveHost = URL(string: "https://hackerrank.com.evil.example/x") ?? base
        let foreignHost = URL(string: "https://example.com/x/tests/t1") ?? base

        #expect(RankBuddyUserActivity.isTrustedFallbackURL(trustedHTTPS))
        #expect(RankBuddyUserActivity.isTrustedFallbackURL(trustedHTTP))
        #expect(!RankBuddyUserActivity.isTrustedFallbackURL(localFile))
        #expect(!RankBuddyUserActivity.isTrustedFallbackURL(customScheme))
        #expect(!RankBuddyUserActivity.isTrustedFallbackURL(deceptiveHost))
        #expect(!RankBuddyUserActivity.isTrustedFallbackURL(foreignHost))
    }
}
