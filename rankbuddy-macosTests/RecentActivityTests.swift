import BuddyAppKit
import Foundation
import os
@testable import rankbuddy_macos
import Testing

/// Coverage for the recent-activity cache (#23): per-collection round-trip, the keep-limit,
/// spanning collections, and account scoping. Uses a uniquely-named on-disk cache per test.
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

    @Test func `recentAll spans the collections`() {
        let store = store(#function)
        let account = UUID()
        store.record([item("t1", .tests)], for: .tests, account: account)
        store.record([item("q1", .questions)], for: .questions, account: account)
        store.record([item("i1", .interviews)], for: .interviews, account: account)
        #expect(Set(store.recentAll(account: account).map(\.id)) == ["t1", "q1", "i1"])
    }

    @Test func `is scoped by account`() {
        let store = store(#function)
        let accountA = UUID()
        let accountB = UUID()
        store.record([item("t1")], for: .tests, account: accountA)
        #expect(store.recent(.tests, account: accountA).map(\.id) == ["t1"])
        #expect(store.recent(.tests, account: accountB).isEmpty)
    }

    // MARK: - Active/upcoming filter (#67)

    private func item(_ id: String, _ collection: FavoriteCollection, subtitle: String?) -> RecentItem {
        RecentItem(collection: collection, id: id, title: id, subtitle: subtitle)
    }

    @Test func `active or upcoming keeps open tests and scheduled interviews`() {
        #expect(item("t", .tests, subtitle: "Active").isActiveOrUpcoming)
        #expect(item("i", .interviews, subtitle: "Scheduled").isActiveOrUpcoming)
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
}
