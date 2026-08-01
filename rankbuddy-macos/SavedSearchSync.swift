//
//  SavedSearchSync.swift
//  rankbuddy-macos
//

import Foundation
import OSLog

nonisolated struct SavedSearchSyncPayload: Codable {
    let searches: [String: [SavedSearch]]
    let modifiedAt: Date
}

/// Mirrors account-scoped saved searches through the same entitlement-gated iCloud KVS boundary
/// as favourites. The payload contains filter configuration only; credentials and API rows never
/// enter iCloud. Whole-snapshot last-writer-wins makes deletion deterministic across Macs.
@MainActor
final class SavedSearchSyncCoordinator {
    static let key = "rankbuddy.savedSearches"
    private static let maximumFutureSkew: TimeInterval = 5 * 60
    private static let logger = Logger(subsystem: "com.adamdangoor.rankbuddy", category: "saved-search-sync")

    private let store: KeyValueSyncStore
    private let defaults: UserDefaults
    private let localToCloudAccountID: (String) -> String?
    private let cloudToLocalAccountID: (String) -> String?
    private var observer: Task<Void, Never>?
    private var isAdopting = false
    private var isActive = false

    init(
        store: KeyValueSyncStore,
        defaults: UserDefaults = .standard,
        localToCloudAccountID: @escaping (String) -> String? = { Optional($0) },
        cloudToLocalAccountID: @escaping (String) -> String? = { Optional($0) }
    ) {
        self.store = store
        self.defaults = defaults
        self.localToCloudAccountID = localToCloudAccountID
        self.cloudToLocalAccountID = cloudToLocalAccountID
    }

    deinit { observer?.cancel() }

    func start() {
        store.onAvailabilityChange = { [weak self] in self?.availabilityChanged() }
        store.onExternalChange = { [weak self] in self?.adoptRemote() }
        observer = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: SavedSearchStore.didChange) {
                self?.pushLocal()
            }
        }
        availabilityChanged()
    }

    private func availabilityChanged() {
        guard store.isAvailable else { isActive = false; return }
        guard !isActive else { return }

        isActive = true
        adoptRemote()
        store.synchronize()
    }

    func adoptRemote() {
        guard store.isAvailable else { return }
        guard let data = store.data(forKey: Self.key) else { pushLocal(); return }
        guard let payload = try? JSONDecoder().decode(SavedSearchSyncPayload.self, from: data) else {
            Self.logger.error("Replacing malformed remote saved searches with local state")
            pushLocal()
            return
        }
        guard payload.modifiedAt.timeIntervalSinceNow <= Self.maximumFutureSkew else {
            Self.logger.error("Rejecting saved-search payload with an implausible future timestamp")
            pushLocal()
            return
        }
        guard SavedSearchStore.modifiedAt(defaults: defaults) <= payload.modifiedAt else {
            pushLocal()
            return
        }

        isAdopting = true
        SavedSearchStore.adopt(
            Self.translated(payload.searches, accountID: cloudToLocalAccountID),
            modifiedAt: payload.modifiedAt,
            defaults: defaults
        )
        isAdopting = false
    }

    func pushLocal() {
        guard !isAdopting, store.isAvailable else { return }

        let payload = SavedSearchSyncPayload(
            searches: Self.translated(
                SavedSearchStore.snapshot(defaults: defaults),
                accountID: localToCloudAccountID
            ),
            modifiedAt: SavedSearchStore.modifiedAt(defaults: defaults)
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }

        store.setData(data, forKey: Self.key)
        store.synchronize()
    }

    static func translated(
        _ snapshot: [String: [SavedSearch]],
        accountID transform: (String) -> String?
    ) -> [String: [SavedSearch]] {
        Dictionary(uniqueKeysWithValues: snapshot.compactMap { key, searches in
            var parts = key.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard let sourceID = parts.last, let targetID = transform(sourceID) else { return nil }

            parts[parts.count - 1] = targetID
            return (parts.joined(separator: "."), searches)
        })
    }
}
