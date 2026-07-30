//
//  RecentActivityTests.swift
//  rankbuddy-macosTests
//

import BuddyAppKit
import Foundation
import os
@testable import rankbuddy_macos
import Testing

/// Coverage for the recent-activity cache (#23): per-collection round-trip, the keep-limit,
/// spanning collections, and account scoping. Uses a uniquely-named on-disk cache per test.
@MainActor
struct RecentActivityTests {
    private func store(_ name: String, limit: Int = 8) -> RecentActivityStore {
        let cache = DiskCache(
            directoryName: "RecentActivity.tests.\(name)",
            logger: Logger(subsystem: "rankbuddy.tests", category: "recents")
        )
        return RecentActivityStore(cache: cache, limit: limit)
    }

    private func item(_ id: String, _ collection: FavoriteCollection = .tests) -> RecentItem {
        RecentItem(collection: collection, id: id, title: id.uppercased(), subtitle: nil)
    }

    @Test func `active items appear in only the selected menu section`() {
        let active = RecentItem(collection: .tests, id: "active", title: "Active", subtitle: "active")
        let archived = RecentItem(collection: .tests, id: "archived", title: "Archived", subtitle: "archived")

        #expect(!active.isIncludedInRecentSection(activeOnly: false))
        #expect(active.isIncludedInRecentSection(activeOnly: true))
        #expect(archived.isIncludedInRecentSection(activeOnly: false))
        #expect(!archived.isIncludedInRecentSection(activeOnly: true))
    }

    @Test func `menu row identity includes account collection and backend ID`() {
        let accountA = UUID()
        let accountB = UUID()
        let test = item("shared", .tests)
        let question = item("shared", .questions)
        let firstTestRow = RecentMenuRow(item: test, accountID: accountA)
        let secondTestRow = RecentMenuRow(item: test, accountID: accountA)

        #expect(firstTestRow.id !=
            RecentMenuRow(item: question, accountID: accountA).id)
        #expect(firstTestRow.id !=
            RecentMenuRow(item: test, accountID: accountB).id)
        #expect(firstTestRow.id == secondTestRow.id)
    }

    @Test func `records and reads back per collection`() {
        let store = store(#function)
        let account = UUID()
        store.record([item("t1"), item("t2")], for: .tests, account: account)
        #expect(store.recent(.tests, account: account).map(\.id) == ["t1", "t2"])
        #expect(store.recent(.questions, account: account).isEmpty)
    }

    @Test func `keeps at most the limit`() {
        let store = store(#function, limit: 2)
        let account = UUID()
        store.record([item("a"), item("b"), item("c"), item("d")], for: .tests, account: account)
        #expect(store.recent(.tests, account: account).map(\.id) == ["a", "b"])
    }

    @Test func `an empty first page preserves recent history`() {
        let store = store(#function)
        let account = UUID()
        store.record([item("t1"), item("t2")], for: .tests, account: account)

        store.record([], for: .tests, account: account)

        #expect(store.recent(.tests, account: account).map(\.id) == ["t1", "t2"])
    }

    @Test func `newly observed items move ahead of retained history`() {
        let store = store(#function, limit: 3)
        let account = UUID()
        store.record([item("a"), item("b"), item("c")], for: .tests, account: account)

        store.record([item("d"), item("b")], for: .tests, account: account)

        #expect(store.recent(.tests, account: account).map(\.id) == ["d", "b", "a"])
    }

    @Test func `recentAll spans the collections`() {
        let store = store(#function)
        let account = UUID()
        store.record([item("t1", .tests)], for: .tests, account: account)
        store.record([item("q1", .questions)], for: .questions, account: account)
        store.record([item("i1", .interviews)], for: .interviews, account: account)
        #expect(Set(store.recentAll(account: account).map(\.id)) == ["t1", "q1", "i1"])
    }

    @Test func `recentAll orders activity across collections`() {
        let store = store(#function)
        let account = UUID()
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        store.record(
            [RecentItem(collection: .tests, id: "test", title: "Test", subtitle: nil, lastSeenAt: older)],
            for: .tests,
            account: account
        )
        store.record(
            [RecentItem(collection: .interviews, id: "interview", title: "Interview",
                        subtitle: nil, lastSeenAt: newer)],
            for: .interviews,
            account: account
        )

        #expect(store.recentAll(account: account).map(\.id) == ["interview", "test"])
    }

    @Test func `is scoped by account`() {
        let store = store(#function)
        let accountA = UUID()
        let accountB = UUID()
        store.record([item("t1")], for: .tests, account: accountA)
        #expect(store.recent(.tests, account: accountA).map(\.id) == ["t1"])
        #expect(store.recent(.tests, account: accountB).isEmpty)
    }

    @Test func `clear removes every collection for only the selected account`() {
        let store = store(#function)
        let accountA = UUID()
        let accountB = UUID()
        store.record([item("t1", .tests)], for: .tests, account: accountA)
        store.record([item("q1", .questions)], for: .questions, account: accountA)
        store.record([item("other", .tests)], for: .tests, account: accountB)

        store.clear(account: accountA)

        #expect(store.recentAll(account: accountA).isEmpty)
        #expect(store.recent(.tests, account: accountB).map(\.id) == ["other"])
    }

    // MARK: - Active/upcoming filter (#67)

    private func item(_ id: String, _ collection: FavoriteCollection, subtitle: String?) -> RecentItem {
        RecentItem(collection: collection, id: id, title: id, subtitle: subtitle)
    }

    @Test func `active or upcoming keeps open tests and scheduled interviews`() {
        #expect(item("t", .tests, subtitle: "Active").isActiveOrUpcoming)
        #expect(item("i", .interviews, subtitle: "Scheduled").isActiveOrUpcoming)
        #expect(item("i", .interviews, subtitle: " ACTIVE ").isActiveOrUpcoming)
        #expect(item("i", .interviews, subtitle: "In progress").isActiveOrUpcoming)
        // Matching is case-insensitive and tolerant of the snake_case status.
        #expect(item("i", .interviews, subtitle: "in_progress").isActiveOrUpcoming)
    }

    @Test func `active or upcoming drops finished, archived, and questions`() {
        #expect(!item("t", .tests, subtitle: "Archived").isActiveOrUpcoming)
        #expect(!item("i", .interviews, subtitle: "Completed").isActiveOrUpcoming)
        #expect(!item("i", .interviews, subtitle: "Cancelled").isActiveOrUpcoming)
        // Questions have no active/upcoming notion, so they're always excluded.
        #expect(!item("q", .questions, subtitle: "Published").isActiveOrUpcoming)
        // A missing subtitle can't be classified as active.
        #expect(!item("t", .tests, subtitle: nil).isActiveOrUpcoming)
    }

    @Test func `active tests respect their cached availability end`() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-07-01T12:00:00Z"))
        let ended = RecentItem(
            collection: .tests,
            id: "ended",
            title: "Ended",
            subtitle: "Active",
            endTime: "2026-07-01T11:59:59Z"
        )
        let upcoming = RecentItem(
            collection: .tests,
            id: "upcoming",
            title: "Upcoming",
            subtitle: "Active",
            startTime: "2026-07-02T12:00:00Z",
            endTime: "2026-07-03T12:00:00Z"
        )

        #expect(!ended.isActiveOrUpcoming(now: now))
        #expect(upcoming.isActiveOrUpcoming(now: now))
    }
}
