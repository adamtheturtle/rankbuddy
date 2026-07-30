//
//  AccountStore.swift
//  rankbuddy-macos
//

import BuddyAppKit
import Foundation
import Observation
import os

/// The concrete multi-account store for RankBuddy.
typealias AccountStore = KeychainAccountStore<Account>

/// Records a persisted-account decoding failure without discarding the source payload.
///
/// `KeychainAccountStore` deliberately accepts a nonthrowing decoder, so RankBuddy performs
/// recovery in its adapter: the corrupt snapshot is copied to another Keychain item before the
/// store is allowed to replace `accounts`. The last backup key is retained in defaults solely so
/// the same payload can reuse its backup on the next launch.
@Observable
@MainActor
final class AccountDataRecovery {
    struct Issue {
        let backupKey: String?
        let decodingError: String

        var replacementAllowed: Bool {
            backupKey != nil
        }
    }

    static let shared = AccountDataRecovery()
    static let backupDefaultsKey = "rankbuddy.accountsRecoveryBackupKey"

    private(set) var issue: Issue?

    func decode(_ data: Data, keychain: KeychainStore) -> [Account] {
        do {
            let accounts = try JSONDecoder().decode([Account].self, from: data)
            issue = nil
            return accounts
        } catch {
            issue = Issue(
                backupKey: backup(data, keychain: keychain),
                decodingError: error.localizedDescription
            )
            return []
        }
    }

    func encode(_ accounts: [Account]) -> Data? {
        guard issue?.replacementAllowed != false else { return nil }
        guard let data = try? JSONEncoder().encode(accounts) else { return nil }

        // A replacement is safe once the original payload has a recovery copy. Clearing the
        // presentation state lets the newly added account become usable without a relaunch.
        issue = nil
        return data
    }

    private func backup(_ data: Data, keychain: KeychainStore) -> String? {
        let defaults = UserDefaults.standard
        if let existingKey = defaults.string(forKey: Self.backupDefaultsKey),
           keychain.readData(account: existingKey) == data {
            return existingKey
        }

        let key = "accounts-recovery-\(UUID().uuidString)"
        guard keychain.write(data, account: key) else { return nil }

        defaults.set(key, forKey: Self.backupDefaultsKey)
        return key
    }
}

extension AccountStore {
    /// Where the current account's id is persisted. Shared so out-of-store callers (the macOS
    /// Service, #46) can resolve "the current account" without a store reference.
    static let currentIDDefaultsKey = "rankbuddy.currentAccountID"

    /// Adds the mock-data demo account if needed, selects it, and returns its id.
    func addDemoIfMissing() -> UUID? {
        if !accounts.contains(where: { $0.isMock && !$0.isBadKeyDemo }) {
            add(.demo)
        }
        guard let demo = accounts.first(where: { $0.isMock && !$0.isBadKeyDemo }) else { return nil }

        currentAccountID = demo.id
        return demo.id
    }

    /// Adds the rejected-token demo account if needed, selects it, and returns its id.
    func addBadKeyDemoIfMissing() -> UUID? {
        if !accounts.contains(where: \.isBadKeyDemo) {
            add(.badKeyDemo)
        }
        guard let demo = accounts.first(where: \.isBadKeyDemo) else { return nil }

        currentAccountID = demo.id
        return demo.id
    }

    /// Builds the RankBuddy account store.
    ///
    /// The Keychain service string is a permanent compatibility contract: it must never
    /// change or existing users would lose their saved accounts. Accounts are serialised
    /// as JSON; there is no legacy store to migrate from and no widget/cache side effects
    /// yet, so those `Config` hooks are no-ops.
    ///
    /// - Parameters:
    ///   - isTesting: when true the store seeds from `seed` and skips all persistence, so
    ///     UI tests and demo mode never touch the real login Keychain.
    ///   - seed: the accounts to seed when `isTesting` is true (e.g. a demo account).
    static func rankBuddy(isTesting: Bool = false, seed: [Account] = []) -> AccountStore {
        let logger = Logger(subsystem: "com.adamdangoor.rankbuddy", category: "accounts")
        let keychain = KeychainStore(service: "com.adamdangoor.rankbuddy", logger: logger)
        let config = Config(
            keychain: keychain,
            accountsKey: "accounts",
            currentIDDefaultsKey: currentIDDefaultsKey,
            showAllAccountsDefaultsKey: "rankbuddy.showAllAccounts",
            encode: { accounts in AccountDataRecovery.shared.encode(accounts) },
            decode: { data in AccountDataRecovery.shared.decode(data, keychain: keychain) },
            isTestingMode: isTesting,
            seedForTesting: { seed },
            migrateIfEmpty: { nil },
            onAccountsChanged: { _ in },
            onCurrentChanged: { _ in },
            // Purge only the deleted account's cached artifacts, preserving other tenants.
            onRemoved: { account in
                RecentActivityStore.shared.clear(account: account.id)
                Task { await RankBuddySpotlightIndex.remove(accountID: account.id) }
            },
            // A changed token/base URL may point at a different backend, so drop every
            // account-scoped artifact that could otherwise show the previous org's data.
            onRekeyed: { account in
                RecentActivityStore.shared.clear(account: account.id)
                Task {
                    await ListPageCache.clear(accountID: account.id)
                    await RankBuddySpotlightIndex.remove(accountID: account.id)
                }
            },
            logger: logger
        )
        return AccountStore(config: config)
    }
}
