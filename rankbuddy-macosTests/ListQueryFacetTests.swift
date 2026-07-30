//
//  ListQueryFacetTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the faceted filtering logic behind the filter bar (#55): facet matching,
/// option derivation, and selection persistence — all pure, so they're tested directly.
@MainActor
struct ListQueryFacetTests {
    @Test func `sort persistence keys use stable restoration identity`() {
        #expect(ListSortPersistence.fieldKey(restorationKey: "tests.account-a")
            != ListSortPersistence.fieldKey(restorationKey: "tests.account-b"))
        #expect(ListSortPersistence.directionKey(restorationKey: "tests.account-a")
            == "sort.v2.tests.account-a.reversed")
        #expect(ListSortPersistence.fieldKey(restorationKey: nil) == nil)
    }

    private struct Row {
        let state: String
        let langs: [String]
    }

    private let rows = [
        Row(state: "Active", langs: ["Python", "Go"]),
        Row(state: "Closed", langs: ["Go"]),
        Row(state: "Active", langs: ["Swift"])
    ]
    private let stateFacet = ListFacet<Row>("state", "State", value: { $0.state })
    private let langFacet = ListFacet<Row>("lang", "Language", values: { $0.langs })

    private func matching(_ selected: [String: Set<String>]) -> [String] {
        rows
            .filter { ListQuery.matchesFacets($0, facets: [stateFacet, langFacet], selected: selected) }
            .map(\.state)
    }

    @Test func `no selection keeps every item`() {
        #expect(matching([:]).count == 3)
        #expect(matching(["state": []]).count == 3)
    }

    @Test func `a single facet keeps only items carrying a chosen value`() {
        #expect(matching(["state": ["Active"]]) == ["Active", "Active"])
    }

    @Test func `a multi-valued facet matches when any value is chosen (OR within a facet)`() {
        // Row 1 has Python, row 3 has Swift; row 2 (Go only) is excluded.
        let kept = rows.filter {
            ListQuery.matchesFacets($0, facets: [langFacet], selected: ["lang": ["Python", "Swift"]])
        }
        #expect(kept.count == 2)
    }

    @Test func `two facets must both be satisfied (AND across facets)`() {
        // Active AND Go → only row 1.
        let kept = rows.filter {
            ListQuery.matchesFacets(
                $0,
                facets: [stateFacet, langFacet],
                selected: ["state": ["Active"], "lang": ["Go"]]
            )
        }
        #expect(kept.count == 1)
    }

    @Test func `facet options are the distinct non-empty values, sorted`() {
        #expect(ListQuery.facetOptions(stateFacet, in: rows) == ["Active", "Closed"])
        #expect(ListQuery.facetOptions(langFacet, in: rows) == ["Go", "Python", "Swift"])
    }

    @Test func `facet options collapse case variants and retain the first display spelling`() {
        let variants = [
            Row(state: "Active", langs: []),
            Row(state: "active", langs: []),
            Row(state: " ACTIVE ", langs: []),
            Row(state: " \t\n ", langs: []),
            Row(state: "Closed", langs: [])
        ]

        #expect(ListQuery.facetOptions(stateFacet, in: variants) == ["Active", "Closed"])
    }

    @Test func `facet matching uses the same case-insensitive semantics as its options`() {
        let lowercase = Row(state: " active\t", langs: [" PYTHON "])

        #expect(
            ListQuery.matchesFacets(
                lowercase,
                facets: [stateFacet, langFacet],
                selected: ["state": ["Active"], "lang": ["Python"]]
            )
        )
        #expect(
            !ListQuery.matchesFacets(
                lowercase,
                facets: [stateFacet],
                selected: ["state": ["Closed"]]
            )
        )
    }

    @Test func `a selection round-trips through persistence and empty sets are dropped`() throws {
        let defaults = try #require(UserDefaults(suiteName: "facet-tests-\(#function)"))
        defer { defaults.removePersistentDomain(forName: "facet-tests-\(#function)") }
        let key = ListQuery.facetsKey("interviews.acct")

        ListQuery.persistFacets(["status": ["Completed"], "stale": []], key: key, defaults: defaults)
        let restored = ListQuery.restoredFacets(key: key, defaults: defaults)
        #expect(restored == ["status": ["Completed"]])

        // Persisting an all-empty selection clears the stored value.
        ListQuery.persistFacets(["status": []], key: key, defaults: defaults)
        #expect(ListQuery.restoredFacets(key: key, defaults: defaults).isEmpty)
    }
}
