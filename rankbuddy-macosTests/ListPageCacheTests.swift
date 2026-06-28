//
//  ListPageCacheTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

@MainActor
struct ListPageCacheTests {
    @Test func `stores and returns a first page by key`() {
        ListPageCache.clear()
        ListPageCache.store(items: ["a", "b"], cursor: "next", for: "tests.acc")

        let cached = ListPageCache.cached([String].self, for: "tests.acc")
        #expect(cached?.items == ["a", "b"])
        #expect(cached?.cursor == "next")
    }

    @Test func `an unknown key is a miss`() {
        ListPageCache.clear()
        #expect(ListPageCache.cached([String].self, for: "missing") == nil)
    }

    @Test func `storing again replaces the entry`() {
        ListPageCache.clear()
        ListPageCache.store(items: [1, 2], cursor: nil, for: "k")
        ListPageCache.store(items: [3], cursor: "c", for: "k")

        let cached = ListPageCache.cached([Int].self, for: "k")
        #expect(cached?.items == [3])
        #expect(cached?.cursor == "c")
    }

    @Test func `clear empties the cache`() {
        ListPageCache.store(items: ["x"], cursor: nil, for: "k")
        ListPageCache.clear()
        #expect(ListPageCache.cached([String].self, for: "k") == nil)
    }

    @Test func `keys are independent`() {
        ListPageCache.clear()
        ListPageCache.store(items: ["tests"], cursor: nil, for: "tests.acc")
        ListPageCache.store(items: ["questions"], cursor: nil, for: "questions.acc")

        #expect(ListPageCache.cached([String].self, for: "tests.acc")?.items == ["tests"])
        #expect(ListPageCache.cached([String].self, for: "questions.acc")?.items == ["questions"])
    }
}
