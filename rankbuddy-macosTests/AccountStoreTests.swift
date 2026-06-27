import BuddyAppKit
import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the `Account` model and the `KeychainAccountStore` adapter (#2, #32).
/// All tests run the store in `isTesting: true` mode, which seeds from memory and skips
/// every Keychain/UserDefaults side effect, so they never touch the real login keychain.
@MainActor
struct AccountStoreTests {
    // MARK: - Account model

    @Test func `baseURL falls back to the default when no override is set`() {
        let account = Account(label: "Work", token: "t")
        #expect(account.baseURL == Account.defaultBaseURL)
        #expect(account.accountID == account.id)
    }

    @Test func `baseURL uses a valid override`() {
        let account = Account(label: "EU", token: "t", baseURLOverride: "https://eu.hackerrank.test")
        #expect(account.baseURL.absoluteString == "https://eu.hackerrank.test")
    }

    @Test func `baseURL ignores an unparseable override`() {
        let account = Account(label: "Bad", token: "t", baseURLOverride: "")
        #expect(account.baseURL == Account.defaultBaseURL)
    }

    @Test func `a changed token points at a different backend`() {
        let original = Account(label: "Work", token: "t1")
        let rekeyed = Account(label: "Work", token: "t2", id: original.id)
        let relabelled = Account(label: "New Label", token: "t1", id: original.id)
        #expect(original.pointsAtDifferentBackend(than: rekeyed))
        // A label change alone does not invalidate caches.
        #expect(!original.pointsAtDifferentBackend(than: relabelled))
    }

    @Test func `a changed base url points at a different backend`() {
        let original = Account(label: "Work", token: "t")
        let moved = Account(label: "Work", token: "t", baseURLOverride: "https://eu.test", id: original.id)
        #expect(original.pointsAtDifferentBackend(than: moved))
    }

    @Test func `account round-trips through JSON without the override`() throws {
        let account = Account(label: "Work", token: "secret")
        let data = try JSONEncoder().encode(account)
        let restored = try JSONDecoder().decode(Account.self, from: data)
        #expect(restored == account)
        #expect(restored.baseURLOverride == nil)
        #expect(restored.userEmail == nil)
    }

    @Test func `the user email round-trips and is absent from older saved accounts`() throws {
        // A captured identity (#72) survives persistence...
        let account = Account(label: "Work", token: "secret", userEmail: "ada@example.com")
        let restored = try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(account))
        #expect(restored.userEmail == "ada@example.com")
        #expect(restored == account)

        // ...and JSON saved before the field existed still decodes (decodeIfPresent → nil).
        let legacy = Data(#"{"id":"00000000-0000-0000-0000-000000000001","label":"Old","token":"t"}"#.utf8)
        #expect(try JSONDecoder().decode(Account.self, from: legacy).userEmail == nil)
    }

    // MARK: - Demo / mock accounts

    @Test func `a normal account is not a mock and the demo accounts are`() {
        #expect(!Account(label: "Work", token: "t").isMock)
        #expect(Account.demo.isMock)
        #expect(Account.demo.token == Account.demoToken)
        // The bad-key demo is also a mock account (its token just gets a 401 from the mock).
        #expect(Account.badKeyDemo.isMock)
        #expect(Account.badKeyDemo.token == Account.badKeyDemoToken)
        #expect(Account.demo.token != Account.badKeyDemo.token)
    }

    @Test func `the demo account stays a mock across a JSON round-trip`() throws {
        // isMock is derived from the reserved token, not a stored field, so it survives
        // persistence with no extra key — a demo account added in the real app keeps
        // routing to the fixtures after relaunch.
        let encoded = try JSONEncoder().encode(Account.demo)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(!json.contains("isMock"))
        #expect(try JSONDecoder().decode(Account.self, from: encoded).isMock)
    }

    // MARK: - Store seeding & selection

    @Test func `an empty store has no accounts and no current id`() {
        let store = AccountStore.rankBuddy(isTesting: true)
        #expect(store.accounts.isEmpty)
        #expect(store.currentAccountID == nil)
        #expect(store.currentAccount == nil)
    }

    @Test func `a seeded store selects the first account as current`() {
        let first = Account(label: "Work", token: "t1")
        let second = Account(label: "EU", token: "t2")
        let store = AccountStore.rankBuddy(isTesting: true, seed: [first, second])
        #expect(store.accounts.count == 2)
        #expect(store.currentAccountID == first.id)
        #expect(store.currentAccount?.id == first.id)
    }

    @Test func `adding to an empty store makes the new account current`() {
        let store = AccountStore.rankBuddy(isTesting: true)
        let account = Account(label: "Work", token: "t")
        store.add(account)
        #expect(store.currentAccountID == account.id)
        #expect(store.accounts.map(\.id) == [account.id])
    }

    @Test func `adding to a populated store leaves the current selection alone`() {
        let first = Account(label: "Work", token: "t1")
        let store = AccountStore.rankBuddy(isTesting: true, seed: [first])
        store.add(Account(label: "EU", token: "t2"))
        #expect(store.currentAccountID == first.id)
    }

    @Test func `update replaces an account in place`() {
        let account = Account(label: "Work", token: "t1")
        let store = AccountStore.rankBuddy(isTesting: true, seed: [account])
        let edited = Account(label: "Work (renamed)", token: "t2", id: account.id)
        store.update(edited)
        #expect(store.accounts.count == 1)
        #expect(store.currentAccount?.label == "Work (renamed)")
        #expect(store.currentAccount?.token == "t2")
    }

    @Test func `update ignores an unknown account`() {
        let account = Account(label: "Work", token: "t1")
        let store = AccountStore.rankBuddy(isTesting: true, seed: [account])
        store.update(Account(label: "Ghost", token: "x"))
        #expect(store.accounts.count == 1)
        #expect(store.currentAccount?.label == "Work")
    }

    @Test func `removing the current account advances the selection`() {
        let first = Account(label: "Work", token: "t1")
        let second = Account(label: "EU", token: "t2")
        let store = AccountStore.rankBuddy(isTesting: true, seed: [first, second])
        store.remove(id: first.id)
        #expect(store.accounts.map(\.id) == [second.id])
        #expect(store.currentAccountID == second.id)
    }

    @Test func `removing the last account clears the selection`() {
        let only = Account(label: "Work", token: "t1")
        let store = AccountStore.rankBuddy(isTesting: true, seed: [only])
        store.remove(id: only.id)
        #expect(store.accounts.isEmpty)
        #expect(store.currentAccountID == nil)
    }

    // MARK: - Merged view

    @Test func `the merged view activates only with two accounts opted in`() {
        let store = AccountStore.rankBuddy(isTesting: true, seed: [
            Account(label: "Work", token: "t1"),
            Account(label: "EU", token: "t2")
        ])
        #expect(!store.isMergedView)
        store.showAllAccounts = true
        #expect(store.isMergedView)
    }

    @Test func `a single account never merges even when opted in`() {
        let store = AccountStore.rankBuddy(isTesting: true, seed: [Account(label: "Work", token: "t1")])
        store.showAllAccounts = true
        #expect(!store.isMergedView)
    }
}
