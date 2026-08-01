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
/// page), so a hydrated section can keep paging. A dedicated global actor serialises encoding,
/// decoding, and file access away from the UI actor. Decode is best-effort: a missing, unreadable,
/// or schema-changed file simply yields `nil` and the list loads fresh.
@globalActor
actor DiskPageCacheActor {
    static let shared = DiskPageCacheActor()
}

@DiskPageCacheActor
enum DiskPageCache {
    /// Tolerates minor wall-clock adjustment while rejecting corrupt or wildly skewed dates.
    private static let maximumFutureSkew: TimeInterval = 5 * 60

    /// A persisted first page: the items, the cursor to the page after them, and the last known total.
    private struct Payload<Item: Codable>: Codable {
        let items: [Item]
        let cursor: String?
        let totalCount: Int?
        let storedAt: Date

        init(items: [Item], cursor: String?, totalCount: Int?, storedAt: Date) {
            self.items = items
            self.cursor = cursor
            self.totalCount = totalCount
            self.storedAt = storedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decode([Item].self, forKey: .items)
            cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
            totalCount = try container.decodeIfPresent(Int.self, forKey: .totalCount)
            storedAt = try container.decodeIfPresent(Date.self, forKey: .storedAt) ?? .distantPast
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

    /// Persists a freshly loaded first page for `key`, replacing any previous file. The cache
    /// actor gives stores and invalidations a clean ordering without blocking the main actor.
    static func store(
        items: [some Codable & Sendable],
        cursor: String?,
        totalCount: Int?,
        for key: String,
        now: Date = Date()
    ) {
        guard isPersistable(key) else { return }
        guard let url = fileURL(for: key),
              let data = try? JSONEncoder().encode(
                  Payload(items: items, cursor: cursor, totalCount: totalCount, storedAt: now)
              )
        else { return }

        // Recreate the directory if `clear()` removed it (or the OS purged the cache) — without
        // this the atomic write would fail silently into a missing parent and never persist.
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    /// The persisted first page for `key`, or `nil` when nothing is stored or the file can't be
    /// decoded into `Item` (e.g. the model's shape changed since it was written).
    static func load<Item: Codable & Sendable>(
        _: [Item].Type,
        for key: String,
        now: Date = Date()
        // swiftlint:disable:next large_tuple
    ) -> (
        items: [Item], cursor: String?, totalCount: Int?
    )? {
        guard isPersistable(key) else {
            if let url = fileURL(for: key) {
                try? FileManager.default.removeItem(at: url)
            }
            return nil
        }
        guard let url = fileURL(for: key) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload<Item>.self, from: data)
        else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        let age = now.timeIntervalSince(payload.storedAt)
        guard age >= -maximumFutureSkew, age <= maximumAge(for: key) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        return (payload.items, payload.cursor, payload.totalCount)
    }

    /// Fast-moving interview/candidate collections expire sooner than catalogue/admin lists.
    private static func maximumAge(for key: String) -> TimeInterval {
        if key.contains(".interviews.") || key.contains(".candidates.") {
            return 15 * 60
        }
        return 60 * 60
    }

    /// Candidate records contain recruiting PII and must remain memory-only.
    private static func isPersistable(_ key: String) -> Bool {
        !key.lowercased().contains("candidate")
    }

    /// Drops every persisted page. Used when an account is re-keyed (its rows may now point at a
    /// different backend) and by tests to stay isolated.
    static func clear() {
        guard let directory else { return }

        try? FileManager.default.removeItem(at: directory)
    }

    /// Drops one test/restoration key without disturbing parallel consumers.
    static func remove(for key: String) {
        guard let url = fileURL(for: key) else { return }

        try? FileManager.default.removeItem(at: url)
    }

    /// Drops only files whose original restoration key belongs to `accountID`.
    static func clear(accountID: UUID) {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil
              )
        else { return }

        for file in files {
            let encodedKey = file.deletingPathExtension().lastPathComponent
            guard let key = encodedKey.removingPercentEncoding,
                  ListPageCache.cacheKey(key, belongsTo: accountID) else { continue }

            try? FileManager.default.removeItem(at: file)
        }
    }
}
