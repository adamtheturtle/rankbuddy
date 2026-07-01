//
//  ListPageCache.swift
//  rankbuddy-macos
//

import Foundation

/// A cache of each list's first page, keyed by its per-account restoration key (#102).
///
/// `LoadableList` is rebuilt from scratch every time the user switches sidebar sections, which
/// resets its `@State` and shows a full-screen "Loading…" spinner on every visit — even for a
/// section viewed seconds ago. This caches the most recent first page so re-entering a section
/// shows its rows instantly while a fresh load refreshes them in the background.
///
/// Two tiers: a fast in-memory store for repeat visits within a launch, backed by `DiskPageCache`
/// so the **first** visit after relaunch is instant too rather than spinning. A memory miss
/// hydrates from disk on demand, and every store writes through to both.
///
/// MainActor-isolated (it only ever runs from the list's MainActor body) and generic over the
/// list's `Item`: each key always maps to the same concrete type, so the stored value casts back
/// cleanly. Lightweight by design — a single first page per section.
@MainActor
enum ListPageCache {
    /// A cached first page: the items and the cursor to the page after them.
    private struct Entry<Item> {
        let items: [Item]
        let cursor: String?
    }

    private static var storage: [String: Any] = [:]

    /// Stores a freshly loaded first page for `key`, replacing any previous entry, and persists
    /// it so the section survives a relaunch.
    static func store(items: [some Codable], cursor: String?, for key: String) {
        storage[key] = Entry(items: items, cursor: cursor)
        DiskPageCache.store(items: items, cursor: cursor, for: key)
    }

    /// The cached first page for `key`, or `nil` when nothing is cached. On an in-memory miss it
    /// hydrates from the on-disk cache (the first visit after relaunch), populating memory so the
    /// next visit is a fast hit.
    static func cached<Item: Codable>(_: [Item].Type, for key: String) -> (items: [Item], cursor: String?)? {
        if let entry = storage[key] as? Entry<Item> {
            return (entry.items, entry.cursor)
        }

        guard let disk = DiskPageCache.load([Item].self, for: key) else { return nil }

        storage[key] = Entry(items: disk.items, cursor: disk.cursor)
        return (disk.items, disk.cursor)
    }

    /// Drops every cached page, in memory and on disk. Used when an account is re-keyed (#102)
    /// and by tests to stay isolated.
    static func clear() {
        storage.removeAll()
        DiskPageCache.clear()
    }
}
