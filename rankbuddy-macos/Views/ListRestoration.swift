//
//  ListRestoration.swift
//  rankbuddy-macos
//

import Foundation

/// Pure decision for restoring a list's prior position on load (#19): given the ids persisted
/// for the last-opened detail and the free-scroll anchor, and the items that just loaded, work
/// out what (if anything) to restore. Kept apart from `LoadableList` so the precedence and the
/// "degrade safely when the object is gone" rules are deterministically unit-testable with mock
/// data, rather than buried in async view state.
nonisolated enum ListRestoration {
    /// What the list should do once a page has loaded.
    enum Action<Item: Identifiable>: Equatable {
        /// Re-open this item's detail (it was the last-viewed object).
        case restoreDetail(Item)
        /// Scroll to this item without opening it (the saved free-scroll anchor).
        case restoreScroll(Item)
        /// Nothing to restore — start at the top.
        case startAtTop

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.restoreDetail(left), .restoreDetail(right)): left.id == right.id
            case let (.restoreScroll(left), .restoreScroll(right)): left.id == right.id
            case (.startAtTop, .startAtTop): true
            default: false
            }
        }
    }

    /// Resolves the restore action. A saved detail wins over a saved scroll anchor; either only
    /// applies when its object is still present in `items`, so a deleted/inaccessible object (or
    /// one on a not-yet-loaded page) degrades to `.none` — no loops, no blank pane.
    static func action<Item: Identifiable>(
        storedDetailID: String?,
        storedAnchorID: String?,
        items: [Item]
    ) -> Action<Item> {
        if let storedDetailID, let item = items.first(where: { String(describing: $0.id) == storedDetailID }) {
            return .restoreDetail(item)
        }

        if let storedAnchorID, let item = items.first(where: { String(describing: $0.id) == storedAnchorID }) {
            return .restoreScroll(item)
        }

        return .startAtTop
    }

    /// Whether the highest-priority saved target may still appear on a later page.
    static func isPending(
        storedDetailID: String?,
        storedAnchorID: String?,
        items: [some Identifiable],
        hasMorePages: Bool
    ) -> Bool {
        guard hasMorePages else { return false }

        let targetID = storedDetailID ?? storedAnchorID
        guard let targetID else { return false }

        return !items.contains { String(describing: $0.id) == targetID }
    }
}
