//
//  DiskPageCacheTests.swift
//  rankbuddy-macosTests
//

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
    }

    @Test func `cached hydrates from disk on a memory miss`() async {
        // Simulate the first visit after relaunch: the page exists only on disk, memory is empty.
        await ListPageCache.clear()
        await DiskPageCache.store(items: ["restored"], cursor: "c", totalCount: nil, for: "disk.hydrate")

        let cached = await ListPageCache.cached([String].self, for: "disk.hydrate")
        #expect(cached?.items == ["restored"])
        #expect(cached?.cursor == "c")
    }
}
