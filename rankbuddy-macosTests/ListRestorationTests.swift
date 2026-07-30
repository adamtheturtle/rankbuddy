//
//  ListRestorationTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

/// Deterministic coverage for the list restore decision (#19): precedence of a saved detail over
/// a saved scroll anchor, and safe degradation when the saved object is no longer present.
struct ListRestorationTests {
    /// A minimal identifiable stand-in for a list item.
    private struct Item: Identifiable, Equatable {
        let id: String
    }

    private let items = [Item(id: "a"), Item(id: "b"), Item(id: "c")]

    @Test func `restores the saved detail when it is still present`() {
        let action = ListRestoration.action(storedDetailID: "b", storedAnchorID: nil, items: items)
        #expect(action == .restoreDetail(Item(id: "b")))
    }

    @Test func `restores the scroll anchor when there is no saved detail`() {
        let action = ListRestoration.action(storedDetailID: nil, storedAnchorID: "c", items: items)
        #expect(action == .restoreScroll(Item(id: "c")))
    }

    @Test func `saved detail wins over a saved scroll anchor`() {
        let action = ListRestoration.action(storedDetailID: "a", storedAnchorID: "c", items: items)
        #expect(action == .restoreDetail(Item(id: "a")))
    }

    @Test func `degrades to top when nothing is saved`() {
        let action = ListRestoration.action(storedDetailID: nil, storedAnchorID: nil, items: items)
        #expect(action == ListRestoration.Action<Item>.startAtTop)
    }

    @Test func `degrades to top when the saved detail is gone`() {
        // A deleted/inaccessible object (or one on a not-yet-loaded page) must not loop or
        // leave a blank pane — it simply leaves the list at the top.
        let action = ListRestoration.action(storedDetailID: "missing", storedAnchorID: nil, items: items)
        #expect(action == ListRestoration.Action<Item>.startAtTop)
    }

    @Test func `falls back to the anchor when the saved detail is gone but the anchor remains`() {
        let action = ListRestoration.action(storedDetailID: "missing", storedAnchorID: "a", items: items)
        #expect(action == .restoreScroll(Item(id: "a")))
    }

    @Test func `degrades to top when both saved ids are gone`() {
        let action = ListRestoration.action(storedDetailID: "x", storedAnchorID: "y", items: items)
        #expect(action == ListRestoration.Action<Item>.startAtTop)
    }

    @Test func `a missing target remains pending while later pages exist`() {
        #expect(ListRestoration.isPending(
            storedDetailID: "later",
            storedAnchorID: nil,
            items: items,
            hasMorePages: true
        ))
        #expect(!ListRestoration.isPending(
            storedDetailID: "later",
            storedAnchorID: nil,
            items: items,
            hasMorePages: false
        ))
    }

    @Test func `the saved detail remains pending even when the scroll anchor is loaded`() {
        #expect(ListRestoration.isPending(
            storedDetailID: "later",
            storedAnchorID: "a",
            items: items,
            hasMorePages: true
        ))
    }

    @Test func `restoration stops pending when its target arrives`() {
        #expect(!ListRestoration.isPending(
            storedDetailID: "b",
            storedAnchorID: nil,
            items: items,
            hasMorePages: true
        ))
    }

    @Test func `fresh rows replace a cached value with the same identity`() {
        let fresh = [Item(id: "a"), Item(id: "b")]

        #expect(ListRestoration.refreshedItem(id: "b", in: fresh) == Item(id: "b"))
        #expect(ListRestoration.refreshedItem(id: "missing", in: fresh) == nil)
    }
}
