//
//  AccountStore.swift
//  rankbuddy-macos
//

import BuddyAppKit
import Foundation
import os

/// The concrete multi-account store for RankBuddy.
typealias AccountStore = KeychainAccountStore<Account>

extension AccountStore {
    /// Where the current account's id is persisted. Shared so out-of-store callers (the macOS
    /// Service, #46) can resolve "the current account" without a store reference.
    static let currentIDDefaultsKey = "rankbuddy.currentAccountID"

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
            encode: { accounts in try? JSONEncoder().encode(accounts) },
            decode: { data in (try? JSONDecoder().decode([Account].self, from: data)) ?? [] },
            isTestingMode: isTesting,
            seedForTesting: { seed },
            migrateIfEmpty: { nil },
            onAccountsChanged: { _ in },
            onCurrentChanged: { _ in },
            // Purge donated Spotlight items so a deleted account's tests/questions/interviews
            // can't linger in system search (#24). The index repopulates with the current
            // account on the next suggestion request.
            onRemoved: { _ in Task { await RankBuddySpotlightIndex.clear() } },
            onRekeyed: { _ in },
            logger: logger
        )
        return AccountStore(config: config)
    }
}
