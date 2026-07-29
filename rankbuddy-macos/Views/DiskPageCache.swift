//
//  DiskPageCache.swift
//  rankbuddy-macos
//

import Foundation

/// On-disk persistence for each list's first page, so a section shows its last-known rows
/// **instantly on the first visit after relaunch** rather than a full-screen spinner — the
/// in-memory `ListPageCache` only survives within a single launch (#102 follow-up).
///
/// One small JSON file per section, keyed by the list's per-account restoration key. The
/// payload is the same first page the in-memory cache holds (items + the cursor to the next
/// page), so a hydrated section can keep paging. Encoding happens on the caller's actor (a
/// single page is tiny) and only the file write is detached, so the UI never blocks on disk.
/// Decode is best-effort: a missing, unreadable, or schema-changed file simply yields `nil`
/// and the list loads fresh.
enum DiskPageCache {
    /// A persisted first page: the items, the cursor to the page after them, and the last known total.
    private struct Payload<Item: Codable>: Codable {
        let items: [Item]
        let cursor: String?
        let totalCount: Int?

        init(items: [Item], cursor: String?, totalCount: Int?) {
            self.items = items
            self.cursor = cursor
            self.totalCount = totalCount
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decode([Item].self, forKey: .items)
            cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
            totalCount = try container.decodeIfPresent(Int.self, forKey: .totalCount)
        }
    }

    /// The cache directory (`Caches/ListPageCache`), created on first use. `nil` only if the
    /// caches directory can't be resolved, in which case persistence is silently skipped.
    private static let directory: URL? = {
        let manager = FileManager.default
        guard let base = manager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }

        let directory = base.appendingPathComponent("ListPageCache", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    /// The file backing `key`. The key is percent-encoded so account-scoped keys are always
    /// valid file names.
    private static func fileURL(for key: String) -> URL? {
        guard let directory else { return nil }

        let name = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }

    /// Persists a freshly loaded first page for `key`, replacing any previous file. Writes
    /// synchronously: a single page is a few kilobytes, it happens just once per section load
    /// (never per frame), and a synchronous write gives a clean ordering against `clear()` — once
    /// `store` returns, the file reflects it, with no detached write racing a later invalidation.
    static func store(items: [some Codable], cursor: String?, totalCount: Int?, for key: String) {
        guard let url = fileURL(for: key),
              let data = try? JSONEncoder().encode(
                  Payload(items: items, cursor: cursor, totalCount: totalCount)
              )
        else { return }

        // Recreate the directory if `clear()` removed it (or the OS purged the cache) — without
        // this the atomic write would fail silently into a missing parent and never persist.
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    // The persisted first page for `key`, or `nil` when nothing is stored or the file can't be
    // decoded into `Item` (e.g. the model's shape changed since it was written).
    // swiftlint:disable:next large_tuple
    static func load<Item: Codable>(_: [Item].Type, for key: String) -> (
        items: [Item], cursor: String?, totalCount: Int?
    )? {
        guard let url = fileURL(for: key),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload<Item>.self, from: data)
        else { return nil }

        return (payload.items, payload.cursor, payload.totalCount)
    }

    /// Drops every persisted page. Used when an account is re-keyed (its rows may now point at a
    /// different backend) and by tests to stay isolated.
    static func clear() {
        guard let directory else { return }

        try? FileManager.default.removeItem(at: directory)
    }
}
