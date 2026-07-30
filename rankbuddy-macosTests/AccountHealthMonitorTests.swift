//
//  AccountHealthMonitorTests.swift
//  rankbuddy-macosTests
//

import BuddyAppKit
import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the mid-session token health monitor (#40), driven through the demo server
/// (the bad-key token 401s; the demo token succeeds).
@MainActor
struct AccountHealthMonitorTests {
    private let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA") ?? UUID()

    private func store(token: String) -> AccountStore {
        AccountStore.rankBuddy(isTesting: true, seed: [Account(label: "A", token: token, id: id)])
    }

    @Test func `a rejected token flags the account, a good one clears it`() async {
        let monitor = AccountHealthMonitor()

        // The bad-key demo 401s → flagged.
        await monitor.check(store: store(token: Account.badKeyDemoToken))
        #expect(monitor.isUnauthorized(id))

        // The same account id with a working token → the flag clears.
        await monitor.check(store: store(token: Account.demoToken))
        #expect(!monitor.isUnauthorized(id))
    }

    @Test func `clearUnauthorized drops a verdict`() async {
        let monitor = AccountHealthMonitor()
        await monitor.check(store: store(token: Account.badKeyDemoToken))
        #expect(monitor.isUnauthorized(id))

        monitor.clearUnauthorized(id)
        #expect(!monitor.isUnauthorized(id))
    }

    @Test func `an account with no token is not probed`() {
        #expect(!AccountHealthMonitor.shouldCheck(Account(label: "x", token: "")))
        #expect(AccountHealthMonitor.shouldCheck(Account(label: "x", token: "abc")))
    }

    @Test func `a captured probe identity does not follow a later account switch`() {
        let first = Account(label: "First", token: "first")
        let second = Account(label: "Second", token: "second")
        let store = AccountStore.rankBuddy(isTesting: true, seed: [first, second])
        store.currentAccountID = second.id

        #expect(AccountHealthMonitor.accountToProbe(first.id, in: store) == first)
        #expect(AccountHealthMonitor.accountToProbe(second.id, in: store) == second)
    }
}
