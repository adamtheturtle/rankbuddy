//
//  DiskPageCacheTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Disk and memory cache checks share process-wide state. Keeping them in one serialized suite
/// prevents a test from clearing another test's fixtures while it is suspended at an `await`.
@Suite(.serialized)
@MainActor
struct PageCacheTests {
    @Test func `stores and loads a first page from disk`() async {
        await DiskPageCache.remove(for: "disk.tests")
        await DiskPageCache.store(items: ["a", "b"], cursor: "next", totalCount: nil, for: "disk.tests")

        let loaded = await DiskPageCache.load([String].self, for: "disk.tests")
        #expect(loaded?.items == ["a", "b"])
        #expect(loaded?.cursor == "next")
    }

    @Test func `load is nil after key removal`() async {
        await DiskPageCache.store(items: ["x"], cursor: nil, totalCount: nil, for: "disk.remove")
        await DiskPageCache.remove(for: "disk.remove")
        #expect(await DiskPageCache.load([String].self, for: "disk.remove") == nil)
    }

    @Test func `a key written by one type does not decode as another`() async {
        await DiskPageCache.remove(for: "disk.mismatch")
        await DiskPageCache.store(items: [1, 2, 3], cursor: nil, totalCount: nil, for: "disk.mismatch")

        // A decode into the wrong element type fails cleanly to nil rather than trapping.
        #expect(await DiskPageCache.load([Bool].self, for: "disk.mismatch") == nil)
        // The failed decode retires the corrupt/schema-incompatible file instead of retrying it.
        #expect(await DiskPageCache.load([Int].self, for: "disk.mismatch") == nil)
    }

    @Test func `cached hydrates from disk on a memory miss`() async {
        // Simulate the first visit after relaunch: the page exists only on disk, memory is empty.
        await ListPageCache.remove(for: "disk.hydrate")
        await DiskPageCache.store(items: ["restored"], cursor: "c", totalCount: nil, for: "disk.hydrate")

        let cached = await ListPageCache.cached([String].self, for: "disk.hydrate")
        #expect(cached?.items == ["restored"])
        #expect(cached?.cursor == "c")
    }

    @Test func `expired pages are removed instead of restored`() async {
        await DiskPageCache.remove(for: "selection.tests.expired")
        let storedAt = Date(timeIntervalSince1970: 1000)
        await DiskPageCache.store(
            items: ["stale"],
            cursor: nil,
            totalCount: nil,
            for: "selection.tests.expired",
            now: storedAt
        )

        let loaded = await DiskPageCache.load(
            [String].self,
            for: "selection.tests.expired",
            now: storedAt.addingTimeInterval(60 * 60 + 1)
        )
        #expect(loaded == nil)
    }

    @Test func `far future pages are removed instead of restored`() async {
        await DiskPageCache.remove(for: "selection.tests.future")
        let now = Date(timeIntervalSince1970: 1000)
        await DiskPageCache.store(
            items: ["future"],
            cursor: nil,
            totalCount: nil,
            for: "selection.tests.future",
            now: now.addingTimeInterval(24 * 60 * 60)
        )

        #expect(await DiskPageCache.load([String].self, for: "selection.tests.future", now: now) == nil)
    }

    @Test func `candidate pages are never persisted`() async {
        let key = "selection.candidates.test.account"
        await DiskPageCache.store(items: ["person@example.com"], cursor: nil, totalCount: 1, for: key)
        #expect(await DiskPageCache.load([String].self, for: key) == nil)
    }
}
