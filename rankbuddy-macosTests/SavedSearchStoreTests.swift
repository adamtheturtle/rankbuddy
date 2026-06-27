//
//  SavedSearchStoreTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for saved-search persistence (#25). Uses a private `UserDefaults` suite so the
/// tests never touch the real defaults and stay isolated.
struct SavedSearchStoreTests {
    private func makeDefaults() -> UserDefaults {
        // A unique suite per test, so the parallel suite can't cross-contaminate.
        UserDefaults(suiteName: "savedsearch.tests.\(UUID().uuidString)") ?? .standard
    }

    @Test func `an empty store loads nothing`() {
        let defaults = makeDefaults()
        #expect(SavedSearchStore.load(restorationKey: "tests.acc", defaults: defaults).isEmpty)
    }

    @Test func `saved searches round-trip through persistence`() {
        let defaults = makeDefaults()
        let searches = [
            SavedSearch(name: "Recent failures", query: "failed", dateRange: "last 7 days"),
            SavedSearch(name: "All time", query: "", dateRange: nil)
        ]
        SavedSearchStore.save(searches, restorationKey: "tests.acc", defaults: defaults)

        let loaded = SavedSearchStore.load(restorationKey: "tests.acc", defaults: defaults)
        #expect(loaded == searches)
    }

    @Test func `searches are scoped by restoration key`() {
        let defaults = makeDefaults()
        SavedSearchStore.save(
            [SavedSearch(name: "A", query: "x", dateRange: nil)],
            restorationKey: "tests.acc1",
            defaults: defaults
        )
        #expect(SavedSearchStore.load(restorationKey: "tests.acc2", defaults: defaults).isEmpty)
        #expect(SavedSearchStore.load(restorationKey: "tests.acc1", defaults: defaults).count == 1)
    }

    @Test func `saving an empty list clears the key`() {
        let defaults = makeDefaults()
        SavedSearchStore.save(
            [SavedSearch(name: "A", query: "x", dateRange: nil)],
            restorationKey: "tests.acc",
            defaults: defaults
        )
        SavedSearchStore.save([], restorationKey: "tests.acc", defaults: defaults)
        #expect(defaults.data(forKey: SavedSearchStore.defaultsKey(for: "tests.acc")) == nil)
    }

    @Test func `a search with no query and no range is empty`() {
        #expect(SavedSearch(name: "x", query: "  ", dateRange: nil).isEmpty)
        #expect(!SavedSearch(name: "x", query: "a", dateRange: nil).isEmpty)
        #expect(!SavedSearch(name: "x", query: "", dateRange: "today").isEmpty)
    }
}
