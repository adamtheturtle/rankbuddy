//
//  ListPageCache.swift
//  rankbuddy-macos
//

import Foundation

/// An in-memory cache of each list's first page, keyed by its per-account restoration key (#102).
///
/// `LoadableList` is rebuilt from scratch every time the user switches sidebar sections, which
/// resets its `@State` and shows a full-screen "Loading…" spinner on every visit — even for a
/// section viewed seconds ago. This caches the most recent first page so re-entering a section
/// shows its rows instantly while a fresh load refreshes them in the background.
///
/// MainActor-isolated (it only ever runs from the list's MainActor body) and generic over the
/// list's `Item`: each key always maps to the same concrete type, so the stored value casts back
/// cleanly. Lightweight by design — a single first page per section — and never persisted, so it
/// holds no stale data across launches.
@MainActor
enum ListPageCache {
    /// A cached first page: the items and the cursor to the page after them.
    private struct Entry<Item> {
        let items: [Item]
        let cursor: String?
    }

    private static var storage: [String: Any] = [:]

    /// Stores a freshly loaded first page for `key`, replacing any previous entry.
    static func store(items: [some Any], cursor: String?, for key: String) {
        storage[key] = Entry(items: items, cursor: cursor)
    }

    /// The cached first page for `key`, or `nil` when nothing is cached (or the cached type does
    /// not match — never expected, since a key always maps to one list's `Item` type).
    static func cached<Item>(_: [Item].Type, for key: String) -> (items: [Item], cursor: String?)? {
        guard let entry = storage[key] as? Entry<Item> else { return nil }

        return (entry.items, entry.cursor)
    }

    /// Drops every cached page. Used by tests to stay isolated.
    static func clear() {
        storage.removeAll()
    }
}
