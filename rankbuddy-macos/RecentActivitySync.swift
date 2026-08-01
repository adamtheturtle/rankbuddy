//
//  RecentActivitySync.swift
//  rankbuddy-macos
//

import Foundation
import OSLog

nonisolated struct RecentActivitySyncPayload: Codable {
    let itemsByAccount: [String: [RecentItem]]
    let modifiedAt: Date
}

/// Synchronizes the bounded, credential-free recent-open history used by RankBuddy's menu bar.
/// The payload carries display names, stable object ids, collection, owner account id, and dates;
/// it never contains tokens, report contents, source code, or candidate records.
@MainActor
final class RecentActivitySyncCoordinator {
    static let key = "rankbuddy.recentActivity"
    private static let maximumFutureSkew: TimeInterval = 5 * 60
    private static let logger = Logger(subsystem: "com.adamdangoor.rankbuddy", category: "recent-sync")

    private let store: KeyValueSyncStore
    private let recents: RecentActivityStore
    private let accountIDs: () -> Set<UUID>
    private let localToCloudAccountID: (UUID) -> String?
    private let cloudToLocalAccountID: (String) -> UUID?
    private var observer: Task<Void, Never>?
    private var isAdopting = false
    private var isActive = false

    init(
        store: KeyValueSyncStore,
        recents: RecentActivityStore = .shared,
        accountIDs: @escaping () -> Set<UUID>,
        localToCloudAccountID: @escaping (UUID) -> String? = { Optional($0).map(\.uuidString) },
        cloudToLocalAccountID: @escaping (String) -> UUID? = { UUID(uuidString: $0) }
    ) {
        self.store = store
        self.recents = recents
        self.accountIDs = accountIDs
        self.localToCloudAccountID = localToCloudAccountID
        self.cloudToLocalAccountID = cloudToLocalAccountID
    }

    deinit { observer?.cancel() }

    func start() {
        store.onAvailabilityChange = { [weak self] in self?.availabilityChanged() }
        store.onExternalChange = { [weak self] in self?.adoptRemote() }
        observer = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: RecentActivityStore.didChange) {
                self?.pushLocal()
            }
        }
        availabilityChanged()
    }

    private func snapshot() -> [String: [RecentItem]] {
        Dictionary(uniqueKeysWithValues: accountIDs().compactMap { accountID in
            let items = recents.recentAll(account: accountID)
            guard !items.isEmpty, let cloudID = localToCloudAccountID(accountID) else { return nil }

            return (cloudID, items)
        })
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
        guard let payload = try? JSONDecoder().decode(RecentActivitySyncPayload.self, from: data) else {
            Self.logger.error("Replacing malformed remote recent history with local state")
            pushLocal()
            return
        }
        guard payload.modifiedAt.timeIntervalSinceNow <= Self.maximumFutureSkew else {
            Self.logger.error("Rejecting recent history with an implausible future timestamp")
            pushLocal()
            return
        }

        let localDate = UserDefaults.standard.object(forKey: RecentActivityStore.modifiedAtKey) as? Date ?? .distantPast
        guard localDate <= payload.modifiedAt else { pushLocal(); return }

        let validIDs = accountIDs()
        let filtered: [UUID: [RecentItem]] = Dictionary(
            uniqueKeysWithValues: payload.itemsByAccount.compactMap { cloudID, items in
                guard let localID = cloudToLocalAccountID(cloudID), validIDs.contains(localID) else { return nil }

                return (localID, items)
            }
        )
        isAdopting = true
        recents.adopt(filtered, accountIDs: validIDs)
        UserDefaults.standard.set(payload.modifiedAt, forKey: RecentActivityStore.modifiedAtKey)
        isAdopting = false
        if filtered.count != payload.itemsByAccount.count {
            pushLocal()
        }
    }

    func pushLocal() {
        guard !isAdopting, store.isAvailable else { return }

        let modifiedAt = UserDefaults.standard.object(forKey: RecentActivityStore.modifiedAtKey)
            as? Date ?? .distantPast
        let payload = RecentActivitySyncPayload(itemsByAccount: snapshot(), modifiedAt: modifiedAt)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        store.setData(data, forKey: Self.key)
        store.synchronize()
    }
}
