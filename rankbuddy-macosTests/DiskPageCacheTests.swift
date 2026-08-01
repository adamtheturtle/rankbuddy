//
//  DiskPageCacheTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// `@MainActor` like `ListPageCacheTests`: both share the process-wide cache (the static store and
/// the on-disk directory), so they must serialise on the main actor rather than interleave.
@MainActor
struct DiskPageCacheTests {
    @Test func `stores and loads a first page from disk`() async {
        await DiskPageCache.clear()
        await DiskPageCache.store(items: ["a", "b"], cursor: "next", totalCount: nil, for: "disk.tests")

        let loaded = await DiskPageCache.load([String].self, for: "disk.tests")
        #expect(loaded?.items == ["a", "b"])
        #expect(loaded?.cursor == "next")
    }

    @Test func `load is nil after clear`() async {
        await DiskPageCache.store(items: ["x"], cursor: nil, totalCount: nil, for: "disk.k")
        await DiskPageCache.clear()
        #expect(await DiskPageCache.load([String].self, for: "disk.k") == nil)
    }

    @Test func `a key written by one type does not decode as another`() async {
        await DiskPageCache.clear()
        await DiskPageCache.store(items: [1, 2, 3], cursor: nil, totalCount: nil, for: "disk.mismatch")

        // A decode into the wrong element type fails cleanly to nil rather than trapping.
        #expect(await DiskPageCache.load([Bool].self, for: "disk.mismatch") == nil)
        // The failed decode retires the corrupt/schema-incompatible file instead of retrying it.
        #expect(await DiskPageCache.load([Int].self, for: "disk.mismatch") == nil)
    }

    @Test func `cached hydrates from disk on a memory miss`() async {
        // Simulate the first visit after relaunch: the page exists only on disk, memory is empty.
        await ListPageCache.clear()
        await DiskPageCache.store(items: ["restored"], cursor: "c", totalCount: nil, for: "disk.hydrate")

        let cached = await ListPageCache.cached([String].self, for: "disk.hydrate")
        #expect(cached?.items == ["restored"])
        #expect(cached?.cursor == "c")
    }

    @Test func `expired pages are removed instead of restored`() async {
        await DiskPageCache.clear()
        let storedAt = Date(timeIntervalSince1970: 1000)
        await DiskPageCache.store(
            items: ["stale"],
            cursor: nil,
            totalCount: nil,
            for: "selection.tests.account",
            now: storedAt
        )

        let loaded = await DiskPageCache.load(
            [String].self,
            for: "selection.tests.account",
            now: storedAt.addingTimeInterval(60 * 60 + 1)
        )
        #expect(loaded == nil)
    }

    @Test func `far future pages are removed instead of restored`() async {
        await DiskPageCache.clear()
        let now = Date(timeIntervalSince1970: 1000)
        await DiskPageCache.store(
            items: ["future"],
            cursor: nil,
            totalCount: nil,
            for: "selection.tests.account",
            now: now.addingTimeInterval(24 * 60 * 60)
        )

        #expect(await DiskPageCache.load([String].self, for: "selection.tests.account", now: now) == nil)
    }

    @Test func `candidate pages are never persisted`() async {
        await DiskPageCache.clear()
        let key = "selection.candidates.test.account"
        await DiskPageCache.store(items: ["person@example.com"], cursor: nil, totalCount: 1, for: key)
        #expect(await DiskPageCache.load([String].self, for: key) == nil)
    }
}
