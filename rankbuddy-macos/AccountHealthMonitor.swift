//
//  AccountHealthMonitor.swift
//  rankbuddy-macos
//

import BuddyAppKit
import Foundation
import HackerRankKit

/// Re-checks the current account's token on a timer (default 30 min) so a token **revoked
/// mid-session** surfaces a banner without needing a section switch or relaunch (#40). A thin
/// app-side wrapper over buddy-kit's generic `AccountHealthMonitor` (#643): the shared monitor
/// owns the timer, the success/unauthorized/transient bucketing, and the verdict set, while this
/// supplies RankBuddy's store-scoped account, its `quota`/`validateToken` probe, and its
/// `HackerRankError.http(401/403)` unauthorized classifier. `@Observable` so the banner updates
/// when the verdict changes; injected (not a singleton) because RankBuddy's `AccountStore` isn't.
@MainActor
@Observable
final class AccountHealthMonitor {
    /// The generic buddy-kit monitor this wraps, built lazily the first time a store is available
    /// (the store is injected at `start`/`check`, not at init, so construction is deferred).
    @ObservationIgnored private var monitor: BuddyAppKit.AccountHealthMonitor<UUID>?

    /// Accounts whose token the API has rejected (401/403) since last checked. Forwarded from the
    /// wrapped monitor so reading it in a view observes the shared monitor's verdict set.
    var unauthorizedAccountIDs: Set<UUID> {
        monitor?.unauthorizedAccountIDs ?? []
    }

    /// Whether an account is worth probing: any account with a token. (The demo tokens are
    /// fine — the mock answers them, so the check is instant and exercises the same path.)
    nonisolated static func shouldCheck(_ account: Account) -> Bool {
        !account.token.isEmpty
    }

    /// Builds (once) the wrapped monitor bound to this store. The probe and the unauthorized
    /// classifier are the app-specific closures the generic monitor takes.
    private func monitor(for store: AccountStore) -> BuddyAppKit.AccountHealthMonitor<UUID> {
        if let monitor { return monitor }

        let monitor = BuddyAppKit.AccountHealthMonitor<UUID>(
            accountToCheck: { [weak store] in
                guard let account = store?.currentAccount, Self.shouldCheck(account) else { return nil }

                return account.id
            },
            probe: { [weak store] _ in
                guard let account = store?.currentAccount else { return }

                try await HackerRankClient(account: account).validateToken()
            },
            isUnauthorized: { error in
                guard case let HackerRankError.http(status, _) = error else { return false }

                return status == 401 || status == 403
            }
        )
        self.monitor = monitor
        return monitor
    }

    /// Starts the periodic check (idempotent): once immediately, then every interval.
    func start(store: AccountStore, every interval: Duration = .seconds(1800)) {
        monitor(for: store).start(every: interval)
    }

    /// Probes the current account's token now (e.g. when the selected account changes).
    func check(store: AccountStore) async {
        await monitor(for: store).check()
    }

    func isUnauthorized(_ accountID: UUID?) -> Bool {
        guard let accountID else { return false }

        return unauthorizedAccountIDs.contains(accountID)
    }

    /// Clears a stale verdict, e.g. when the account's token is edited; a later check re-flags
    /// it if the new token is also bad.
    func clearUnauthorized(_ accountID: UUID) {
        monitor?.clearUnauthorized(accountID)
    }
}
