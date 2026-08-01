//
//  SavedSearchStoreTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for saved-search persistence (#25). Uses a private `UserDefaults` suite so the
/// tests never touch the real defaults and stay isolated.
@MainActor
struct SavedSearchStoreTests {
    @Test func `cloud translation replaces only the account component`() {
        let search = SavedSearch(name: "Backend", query: "swift", dateRange: nil)
        let translated = SavedSearchSyncCoordinator.translated(
            ["selection.tests.local-id": [search]],
            accountID: { $0 == "local-id" ? "cloud-id" : nil }
        )

        #expect(translated == ["selection.tests.cloud-id": [search]])
    }

    @Test func `cloud translation drops state for an unmatched account`() {
        let translated = SavedSearchSyncCoordinator.translated(
            ["selection.tests.removed": [SavedSearch(name: "Old", query: "old", dateRange: nil)]],
            accountID: { _ in nil }
        )

        #expect(translated.isEmpty)
    }

    @Test func `snapshot and adoption round trip all list scopes`() throws {
        let sourceName = "saved-search-sync-source-\(UUID())"
        let targetName = "saved-search-sync-target-\(UUID())"
        let source = try #require(UserDefaults(suiteName: sourceName))
        let target = try #require(UserDefaults(suiteName: targetName))
        defer {
            source.removePersistentDomain(forName: sourceName)
            target.removePersistentDomain(forName: targetName)
        }
        SavedSearchStore.save(
            [SavedSearch(name: "Backend", query: "swift", dateRange: nil)],
            restorationKey: "selection.tests.account-a",
            defaults: source
        )
        SavedSearchStore.save(
            [SavedSearch(name: "Recent", query: "", dateRange: "today")],
            restorationKey: "selection.questions.account-b",
            defaults: source
        )

        let snapshot = SavedSearchStore.snapshot(defaults: source)
        let modifiedAt = SavedSearchStore.modifiedAt(defaults: source)
        SavedSearchStore.adopt(snapshot, modifiedAt: modifiedAt, defaults: target)

        #expect(SavedSearchStore.snapshot(defaults: target) == snapshot)
        #expect(abs(SavedSearchStore.modifiedAt(defaults: target).timeIntervalSince(modifiedAt)) < 1)
    }

    @Test func `adopting an empty snapshot propagates deletions`() throws {
        let suiteName = "saved-search-sync-delete-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        SavedSearchStore.save(
            [SavedSearch(name: "Old", query: "stale", dateRange: nil)],
            restorationKey: "selection.tests.account-a",
            defaults: defaults
        )

        SavedSearchStore.adopt([:], modifiedAt: Date(), defaults: defaults)

        #expect(SavedSearchStore.snapshot(defaults: defaults).isEmpty)
    }

    private func makeDefaults() -> UserDefaults {
        // A unique suite per test, so the parallel suite can't cross-contaminate.
        UserDefaults(suiteName: "savedsearch.tests.\(UUID().uuidString)") ?? .standard
    }

    @Test func `clearing an account preserves other accounts`() {
        let account = UUID()
        let other = UUID()
        let defaults = makeDefaults()
        SavedSearchStore.save(
            [SavedSearch(name: "Old org", query: "secret", dateRange: nil)],
            restorationKey: "selection.tests.\(account)",
            defaults: defaults
        )
        SavedSearchStore.save(
            [SavedSearch(name: "Other", query: "safe", dateRange: nil)],
            restorationKey: "selection.tests.\(other)",
            defaults: defaults
        )

        SavedSearchStore.clear(accountID: account, defaults: defaults)

        #expect(SavedSearchStore.load(
            restorationKey: "selection.tests.\(account)", defaults: defaults
        ).isEmpty)
        #expect(SavedSearchStore.load(
            restorationKey: "selection.tests.\(other)", defaults: defaults
        ).count == 1)
    }

    @Test func `an empty store loads nothing`() {
        let defaults = makeDefaults()
        #expect(SavedSearchStore.load(restorationKey: "tests.acc", defaults: defaults).isEmpty)
    }

    @Test func `names are trimmed and capped at the declared limit`() {
        let search = SavedSearch(
            name: "  \(String(repeating: "x", count: 100))  ",
            query: "q",
            dateRange: nil
        )

        #expect(search.name.count == SavedSearch.maxNameLength)
        #expect(search.name == String(repeating: "x", count: SavedSearch.maxNameLength))
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

    @Test func `only the most recent saved searches are retained`() {
        let defaults = makeDefaults()
        let searches = (0 ... SavedSearchStore.maximumCount).map {
            SavedSearch(name: "Search \($0)", query: "\($0)", dateRange: nil)
        }
        SavedSearchStore.save(searches, restorationKey: "tests.acc", defaults: defaults)

        let loaded = SavedSearchStore.load(restorationKey: "tests.acc", defaults: defaults)
        #expect(loaded.count == SavedSearchStore.maximumCount)
        #expect(loaded.first?.name == "Search 1")
        #expect(loaded.last?.name == "Search \(SavedSearchStore.maximumCount)")
    }

    @Test func `corrupt records preserve raw data and recover valid searches`() throws {
        let defaults = makeDefaults()
        let valid = SavedSearch(name: "Valid", query: "swift", dateRange: nil)
        let validObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(valid))
        let raw = try JSONSerialization.data(withJSONObject: [
            validObject,
            ["id": "not-a-uuid", "name": "Broken", "query": "x"]
        ])
        let restorationKey = "tests.acc"
        defaults.set(raw, forKey: SavedSearchStore.defaultsKey(for: restorationKey))

        let loaded = SavedSearchStore.load(restorationKey: restorationKey, defaults: defaults)

        #expect(loaded == [valid])
        #expect(defaults.data(forKey: SavedSearchStore.recoveryKey(for: restorationKey)) == raw)
        let repaired = try #require(defaults.data(forKey: SavedSearchStore.defaultsKey(for: restorationKey)))
        #expect(try JSONDecoder().decode([SavedSearch].self, from: repaired) == [valid])
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

    @Test func `successful replacement retires recovery data`() {
        let defaults = makeDefaults()
        let restorationKey = "tests.acc"
        defaults.set(Data("old".utf8), forKey: SavedSearchStore.recoveryKey(for: restorationKey))

        SavedSearchStore.save(
            [SavedSearch(name: "Replacement", query: "swift", dateRange: nil)],
            restorationKey: restorationKey,
            defaults: defaults
        )

        #expect(defaults.data(forKey: SavedSearchStore.recoveryKey(for: restorationKey)) == nil)
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

    @Test func `a search with no query, range, or facets is empty`() {
        #expect(SavedSearch(name: "x", query: "  ", dateRange: nil).isEmpty)
        #expect(!SavedSearch(name: "x", query: "a", dateRange: nil).isEmpty)
        #expect(!SavedSearch(name: "x", query: "", dateRange: "today").isEmpty)
        #expect(!SavedSearch(name: "x", query: "", dateRange: nil, facets: ["state": ["Active"]]).isEmpty)
        // An all-empty facet set carries no constraint, so it's still empty.
        #expect(SavedSearch(name: "x", query: "", dateRange: nil, facets: ["state": []]).isEmpty)
    }

    @Test func `saved search queries use trimmed list semantics`() {
        let search = SavedSearch(name: "Backend", query: " backend \n", dateRange: nil)

        #expect(search.query == "backend")
        #expect(search.matches(query: "\tbackend ", dateRange: nil, facets: [:]))
    }

    @Test func `saved search names match case insensitively after trimming`() {
        #expect(SavedSearch.namesMatch(" Backend ", "backend"))
        #expect(!SavedSearch.namesMatch("Backend", "Frontend"))
    }

    @Test func `facet selections round-trip through persistence`() {
        let defaults = makeDefaults()
        let searches = [
            SavedSearch(name: "JS failures", query: "failed", dateRange: "last 7 days",
                        facets: ["language": ["JavaScript", "TypeScript"], "status": ["Failed"]])
        ]
        SavedSearchStore.save(searches, restorationKey: "tests.acc", defaults: defaults)

        let loaded = SavedSearchStore.load(restorationKey: "tests.acc", defaults: defaults)
        #expect(loaded == searches)
        #expect(loaded.first?.facetSelection == ["language": ["JavaScript", "TypeScript"], "status": ["Failed"]])
    }

    @Test func `a snapshot saved before facets existed still decodes`() throws {
        // A legacy payload with no `facets` key, as written before facet capture.
        let legacy = """
        [{"id":"\(UUID().uuidString)","name":"Old","query":"x","dateRange":"today"}]
        """
        let decoded = try JSONDecoder().decode([SavedSearch].self, from: Data(legacy.utf8))
        #expect(decoded.first?.facets.isEmpty == true)
        #expect(decoded.first?.query == "x")
    }

    @Test func `matches reflects the live query, range, and facets`() {
        let search = SavedSearch(name: "x", query: "go", dateRange: "today", facets: ["status": ["Open"]])
        #expect(search.matches(query: "go", dateRange: "today", facets: ["status": ["Open"]]))
        // Empty per-facet sets on the live side are ignored, not treated as a mismatch.
        #expect(search.matches(query: "go", dateRange: "today", facets: ["status": ["Open"], "lang": []]))
        #expect(!search.matches(query: "go", dateRange: "today", facets: ["status": ["Closed"]]))
        #expect(!search.matches(query: "rust", dateRange: "today", facets: ["status": ["Open"]]))
        #expect(!search.matches(query: "go", dateRange: nil, facets: ["status": ["Open"]]))
    }

    @Test func `validation removes facet IDs the current list no longer declares`() {
        let search = SavedSearch(
            name: "Legacy",
            query: "",
            dateRange: nil,
            facets: ["status": ["Open"], "removed_team": ["Platform"]]
        )

        let validated = search.retainingFacetIDs(["status", "language"])

        #expect(validated.facetSelection == ["status": ["Open"]])
        #expect(validated.id == search.id)
        #expect(validated.name == search.name)
    }

    @Test func `validation clears a date range the current app no longer offers`() {
        let search = SavedSearch(name: "Legacy", query: "swift", dateRange: "previous quarter")

        let validated = search.retainingDateRanges(["today", "last 7 days"])

        #expect(validated.dateRange == nil)
        #expect(validated.query == "swift")
        #expect(
            SavedSearch(name: "Current", query: "", dateRange: "today")
                .retainingDateRanges(["today"])
                .dateRange == "today"
        )
    }

    @Test func `duplicate persisted IDs are repaired and saved`() throws {
        let defaults = try #require(UserDefaults(suiteName: "saved-search-\(#function)"))
        defaults.removePersistentDomain(forName: "saved-search-\(#function)")
        let duplicateID = UUID()
        let searches = [
            SavedSearch(name: "One", query: "one", dateRange: nil, id: duplicateID),
            SavedSearch(name: "Two", query: "two", dateRange: nil, id: duplicateID)
        ]
        SavedSearchStore.save(searches, restorationKey: "tests.acc", defaults: defaults)

        let repaired = SavedSearchStore.load(restorationKey: "tests.acc", defaults: defaults)
        #expect(Set(repaired.map(\.id)).count == 2)
        #expect(SavedSearchStore.load(restorationKey: "tests.acc", defaults: defaults) == repaired)
    }
}
