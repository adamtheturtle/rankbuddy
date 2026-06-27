import BuddyAppKit
import Foundation

/// Re-checks the current account's token on a timer (default 30 min) so a token **revoked
/// mid-session** surfaces a banner without needing a section switch or relaunch (#40). Mirrors
/// PadBuddy's `AccountHealthMonitor`. `@Observable` so the banner updates when the verdict
/// changes; injected (not a singleton) because RankBuddy's `AccountStore` isn't one.
@MainActor
@Observable
final class AccountHealthMonitor {
    /// Accounts whose token the API has rejected (401/403) since it was last checked.
    private(set) var unauthorizedAccountIDs: Set<UUID> = []
    private var task: Task<Void, Never>?

    /// Whether an account is worth probing: any account with a token. (The demo tokens are
    /// fine — the mock answers them, so the check is instant and exercises the same path.)
    nonisolated static func shouldCheck(_ account: Account) -> Bool {
        !account.token.isEmpty
    }

    /// Starts the periodic check (idempotent): once immediately, then every interval.
    func start(store: AccountStore, every interval: Duration = .seconds(1800)) {
        guard task == nil else { return }

        task = Task { [weak self] in
            await self?.check(store: store)
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }

                await self?.check(store: store)
            }
        }
    }

    /// Probes the current account's token. A rejection (401/403) flags it; a success clears any
    /// prior flag; transient errors (offline, 5xx, decode) leave the verdict unchanged so a
    /// blip doesn't wrongly claim the key is bad.
    func check(store: AccountStore) async {
        guard let account = store.currentAccount, Self.shouldCheck(account) else { return }

        do {
            try await HackerRankClient(account: account).validateToken()
            unauthorizedAccountIDs.remove(account.id)
        } catch let HackerRankError.http(status, _) where status == 401 || status == 403 {
            unauthorizedAccountIDs.insert(account.id)
        } catch {
            // Transient — keep the previous verdict.
        }
    }

    func isUnauthorized(_ accountID: UUID?) -> Bool {
        guard let accountID else { return false }

        return unauthorizedAccountIDs.contains(accountID)
    }

    /// Clears a stale verdict, e.g. when the account's token is edited; a later check re-flags
    /// it if the new token is also bad.
    func clearUnauthorized(_ accountID: UUID) {
        unauthorizedAccountIDs.remove(accountID)
    }
}
