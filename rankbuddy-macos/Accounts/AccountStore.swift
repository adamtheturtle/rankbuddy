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
            // A changed token/base URL may point at a different backend, so drop the cached
            // first pages (memory and disk) that could otherwise show another org's rows (#102).
            onRekeyed: { _ in ListPageCache.clear() },
            logger: logger
        )
        return AccountStore(config: config)
    }
}
