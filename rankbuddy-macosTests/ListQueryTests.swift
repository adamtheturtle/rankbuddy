//
//  ListQueryTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the list-shaping helpers extracted from LoadableList (#19/#44).
struct ListQueryTests {
    private struct Row { let name: String }

    @Test func `filtered matches the query case-insensitively`() {
        let rows = [Row(name: "Backend Screen"), Row(name: "Frontend"), Row(name: "SRE")]
        let result = ListQuery.filtered(rows, query: "end", searchableText: \.name, date: nil, dateRange: nil)
        #expect(result.map(\.name) == ["Backend Screen", "Frontend"])
    }

    @Test func `an empty query keeps everything`() {
        let rows = [Row(name: "a"), Row(name: "b")]
        #expect(ListQuery.filtered(rows, query: "  ", searchableText: \.name, date: nil, dateRange: nil).count == 2)
    }

    @Test func `the filter key is scoped by restoration key, nil without one`() {
        #expect(ListQuery.filterKey("tests.acc") == "filter.tests.acc")
        #expect(ListQuery.filterKey(nil) == nil)
    }

    @Test func `a range round-trips and an unknown stored value is ignored`() {
        let defaults = UserDefaults(suiteName: "listquery.tests.\(UUID().uuidString)") ?? .standard
        ListQuery.persistRange("last 7 days", key: "k", defaults: defaults)
        #expect(ListQuery.restoredRange(key: "k", defaults: defaults) == "last 7 days")

        // Clearing removes it.
        ListQuery.persistRange(nil, key: "k", defaults: defaults)
        #expect(ListQuery.restoredRange(key: "k", defaults: defaults) == nil)

        // A stale/unknown value is treated as no filter.
        defaults.set("nonsense", forKey: "k")
        #expect(ListQuery.restoredRange(key: "k", defaults: defaults) == nil)
    }
}
