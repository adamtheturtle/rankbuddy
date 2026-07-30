//
//  ListPageCacheTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

@MainActor
struct ListPageCacheTests {
    @Test func `stores and returns a first page by key`() async {
        await ListPageCache.clear()
        await ListPageCache.store(items: ["a", "b"], cursor: "next", totalCount: nil, for: "tests.acc")

        let cached = await ListPageCache.cached([String].self, for: "tests.acc")
        #expect(cached?.items == ["a", "b"])
        #expect(cached?.cursor == "next")
    }

    @Test func `an unknown key is a miss`() async {
        await ListPageCache.clear()
        #expect(await ListPageCache.cached([String].self, for: "missing") == nil)
    }

    @Test func `storing again replaces the entry`() async {
        await ListPageCache.clear()
        await ListPageCache.store(items: [1, 2], cursor: nil, totalCount: nil, for: "k")
        await ListPageCache.store(items: [3], cursor: "c", totalCount: nil, for: "k")

        let cached = await ListPageCache.cached([Int].self, for: "k")
        #expect(cached?.items == [3])
        #expect(cached?.cursor == "c")
    }

    @Test func `clear empties the cache`() async {
        await ListPageCache.store(items: ["x"], cursor: nil, totalCount: nil, for: "k")
        await ListPageCache.clear()
        #expect(await ListPageCache.cached([String].self, for: "k") == nil)
    }

    @Test func `account clear preserves unrelated cache entries`() async {
        let changedID = UUID()
        let otherID = UUID()
        let changedKey = "selection.tests.\(changedID)"
        let otherKey = "selection.tests.\(otherID)"
        await ListPageCache.store(items: ["changed"], cursor: nil, totalCount: nil, for: changedKey)
        await ListPageCache.store(items: ["other"], cursor: nil, totalCount: nil, for: otherKey)

        await ListPageCache.clear(accountID: changedID)

        #expect(await ListPageCache.cached([String].self, for: changedKey) == nil)
        #expect(await ListPageCache.cached([String].self, for: otherKey)?.items == ["other"])
    }

    @Test func `keys are independent`() async {
        await ListPageCache.clear()
        await ListPageCache.store(items: ["tests"], cursor: nil, totalCount: nil, for: "tests.acc")
        await ListPageCache.store(items: ["questions"], cursor: nil, totalCount: nil, for: "questions.acc")

        #expect(await ListPageCache.cached([String].self, for: "tests.acc")?.items == ["tests"])
        #expect(await ListPageCache.cached([String].self, for: "questions.acc")?.items == ["questions"])
    }
}
