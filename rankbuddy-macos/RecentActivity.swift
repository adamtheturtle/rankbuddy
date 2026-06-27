//
//  RecentActivity.swift
//  rankbuddy-macos
//

import BuddyAppKit
import Foundation
import os

/// A lightweight, non-secret record of an item the user has recently seen in a list, cached so
/// the menu bar can show recent activity without a second network stack (#23). Only display
/// metadata is stored — no tokens, scores, or candidate PII.
nonisolated struct RecentItem: Codable, Hashable, Identifiable {
    let collection: FavoriteCollection
    let id: String
    let title: String
    var subtitle: String?

    /// Whether this item counts as "active or upcoming" for the menu-bar filter (#67): an
    /// open test or a scheduled / in-progress interview. Questions (no active/upcoming notion)
    /// and finished/archived items are excluded. Matches on the cached `subtitle`, which the
    /// lists record as the test state / interview status — the only signal available offline.
    var isActiveOrUpcoming: Bool {
        let status = subtitle?.lowercased()
        switch collection {
        case .tests:
            return status == "active"
        case .interviews:
            return status == "scheduled" || status == "in progress" || status == "in_progress"
        default:
            return false
        }
    }
}

/// Caches the most-recently-listed items per account/collection on disk (#23), via buddy-kit's
/// `DiskCache`. The main lists record their first page as they load; the menu bar reads the
/// cache (no extra fetch). The cache lives in Application Support, so it's shared in-process
/// between the main window and the menu bar — not across an App Group (a widget extension, #16,
/// would need that).
nonisolated struct RecentActivityStore {
    static let shared = Self()

    /// How many items per collection to keep.
    static let perCollectionLimit = 8

    private let cache: DiskCache
    private let limit: Int

    init(
        cache: DiskCache = DiskCache(
            directoryName: "RecentActivity",
            logger: Logger(subsystem: "com.adamdangoor.rankbuddy", category: "recents")
        ),
        limit: Int = Self.perCollectionLimit
    ) {
        self.cache = cache
        self.limit = limit
    }

    /// Records the most-recently-listed items for a collection (keeping at most `limit`).
    func record(_ items: [RecentItem], for collection: FavoriteCollection, account: UUID) {
        cache.save(Array(items.prefix(limit)), kind: collection.rawValue, account: account)
    }

    /// The cached recent items for one collection.
    func recent(_ collection: FavoriteCollection, account: UUID) -> [RecentItem] {
        cache.load([RecentItem].self, kind: collection.rawValue, account: account) ?? []
    }

    /// All cached recent items for an account, across the top-level collections.
    func recentAll(account: UUID) -> [RecentItem] {
        FavoriteCollection.allCases.flatMap { recent($0, account: account) }
    }
}
