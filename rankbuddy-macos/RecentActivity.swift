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
    var startTime: String?
    var endTime: String?
    var lastSeenAt: Date?

    init(
        collection: FavoriteCollection,
        id: String,
        title: String,
        subtitle: String?,
        startTime: String? = nil,
        endTime: String? = nil,
        lastSeenAt: Date? = Date()
    ) {
        self.collection = collection
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.startTime = startTime
        self.endTime = endTime
        self.lastSeenAt = lastSeenAt
    }

    /// Whether this item counts as "active or upcoming" for the menu-bar filter (#67): an
    /// open test or a scheduled / in-progress interview. Questions (no active/upcoming notion)
    /// and finished/archived items are excluded. Matches on the cached `subtitle`, which the
    /// lists record as the test state / interview status — the only signal available offline.
    var isActiveOrUpcoming: Bool {
        isActiveOrUpcoming(now: Date())
    }

    func isActiveOrUpcoming(now: Date) -> Bool {
        let status = subtitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch collection {
        case .tests:
            guard status == "active" else { return false }

            if let end = Self.parseWindowDate(endTime), now >= end {
                return false
            }
            return true

        case .interviews:
            guard let status else { return false }

            if let end = Self.parseWindowDate(endTime), now >= end {
                return false
            }

            return status == "active" || LivenessDigest.isNotificationEligible(status: status)

        default:
            return false
        }
    }

    /// Active items are rendered in the higher-priority menu section unless that section is
    /// intentionally replacing Recent via the active-only preference.
    func isIncludedInRecentSection(activeOnly: Bool) -> Bool {
        activeOnly ? isActiveOrUpcoming : !isActiveOrUpcoming
    }

    private static func parseWindowDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

/// Supplies SwiftUI with an identity that remains unique when backend IDs are reused between
/// collections or accounts.
nonisolated struct RecentMenuRow: Identifiable {
    struct Identity: Hashable {
        let accountID: UUID
        let collection: FavoriteCollection
        let itemID: String
    }

    let item: RecentItem
    let id: Identity

    var accountID: UUID {
        id.accountID
    }

    init(item: RecentItem, accountID: UUID) {
        self.item = item
        id = Identity(accountID: accountID, collection: item.collection, itemID: item.id)
    }
}

/// Caches the most-recently-listed items per account/collection on disk (#23), via buddy-kit's
/// `DiskCache`. The main lists record their first page as they load; the menu bar reads the
/// cache (no extra fetch). The cache lives in Application Support, so it's shared in-process
/// between the main window and the menu bar — not across an App Group (a widget extension, #16,
/// would need that).
nonisolated struct RecentActivityStore {
    static let shared = Self()

    /// Retain enough from any one collection to satisfy the menu's largest selectable count.
    static let perCollectionLimit = MenuBarPreferences.maxRecentCount

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

    /// Merges newly observed items into the collection's MRU history. An empty snapshot carries
    /// no activity signal, so it never erases previously observed items.
    func record(_ items: [RecentItem], for collection: FavoriteCollection, account: UUID) {
        guard !items.isEmpty else { return }

        var seen = Set(items.map(\.id))
        let retained = recent(collection, account: account).filter {
            seen.insert($0.id).inserted
        }
        cache.save(Array((items + retained).prefix(limit)), kind: collection.rawValue, account: account)
    }

    /// The cached recent items for one collection.
    func recent(_ collection: FavoriteCollection, account: UUID) -> [RecentItem] {
        cache.load([RecentItem].self, kind: collection.rawValue, account: account) ?? []
    }

    /// All cached recent items for an account, across the top-level collections.
    func recentAll(account: UUID) -> [RecentItem] {
        FavoriteCollection.allCases
            .flatMap { recent($0, account: account) }
            .sorted { ($0.lastSeenAt ?? .distantPast) > ($1.lastSeenAt ?? .distantPast) }
    }

    /// All cached rows for a set of accounts, retaining each item's owner for deep links.
    func recentAll(accounts: [UUID]) -> [RecentMenuRow] {
        accounts
            .flatMap { accountID in
                recentAll(account: accountID).map { RecentMenuRow(item: $0, accountID: accountID) }
            }
            .sorted { ($0.item.lastSeenAt ?? .distantPast) > ($1.item.lastSeenAt ?? .distantPast) }
    }

    /// Removes every recent-activity snapshot belonging to an account.
    func clear(account: UUID) {
        for collection in FavoriteCollection.allCases {
            cache.delete(kind: collection.rawValue, account: account)
        }
    }
}
