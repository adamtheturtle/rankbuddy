//
//  AccountStoreTests.swift
//  rankbuddy-macosTests
//

import BuddyAppKit
import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the `Account` model and the `KeychainAccountStore` adapter (#2, #32).
/// All tests run the store in `isTesting: true` mode, which seeds from memory and skips
/// every Keychain/UserDefaults side effect, so they never touch the real login keychain.
@MainActor
struct AccountStoreTests {
    @Test func `scope assessment reports unavailable probes separately`() {
        let warning = AccountScopeAssessment.warning([
            ("Tests", .authorized),
            ("Questions", .refused),
            ("Teams", .unavailable)
        ])

        #expect(warning?.contains("isn't authorized for: Questions") == true)
        #expect(warning?.contains("couldn't be verified for: Teams") == true)
    }

    @Test func `account descriptions conflict after trimming and case normalization`() {
        #expect(Account.labelsConflict(" Work ", "work"))
        #expect(!Account.labelsConflict("Work", "Personal"))
        #expect(!Account.labelsConflict(" ", ""))
    }

    @Test func `credential comparison normalization trims stored and edited values`() {
        #expect(AccountEditor.normalizedCredential(" token \n") == "token")
        #expect(AccountEditor.normalizedCredential(nil).isEmpty)
    }

    @Test func `account descriptions are bounded when created and decoded`() throws {
        let oversized = String(repeating: "A", count: Account.maximumLabelLength + 20)
        #expect(Account(label: oversized, token: "t").label.count == Account.maximumLabelLength)

        let source = Account(label: "short", token: "t")
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
        object["label"] = oversized
        let decoded = try JSONDecoder().decode(
            Account.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(decoded.label.count == Account.maximumLabelLength)
    }

    // MARK: - Account model

    @Test func `baseURL falls back to the default when no override is set`() {
        let account = Account(label: "Work", token: "t")
        #expect(account.baseURL == Account.defaultBaseURL)
        #expect(account.accountID == account.id)
    }

    @Test func `baseURL uses a valid override`() {
        let account = Account(label: "EU", token: "t", baseURLOverride: " https://eu.hackerrank.test ")
        #expect(account.baseURL.absoluteString == "https://eu.hackerrank.test")
        #expect(account.parsedBaseURLOverride == URL(string: "https://eu.hackerrank.test"))
        #expect(!account.hasMalformedBaseURLOverride)
    }

    @Test func `baseURL ignores an unparseable override`() {
        let account = Account(label: "Bad", token: "t", baseURLOverride: "")
        #expect(account.baseURL == Account.defaultBaseURL)
        #expect(!account.hasMalformedBaseURLOverride)
    }

    @Test func `non-empty invalid base URL overrides are malformed`() {
        for raw in ["htps://hackerrank.internal", "hackerrank.internal", "ftp://hackerrank.internal", "https://"] {
            let account = Account(label: "Bad", token: "t", baseURLOverride: raw)
            #expect(account.hasMalformedBaseURLOverride, "\(raw) should be malformed")
            #expect(account.parsedBaseURLOverride == nil, "\(raw) should not parse as an override")
        }
    }

    @Test func `server identity folds cosmetic URL spelling differences`() {
        let canonical = Account(label: "A", token: "t", baseURLOverride: "https://hackerrank.example").serverIdentity
        for spelling in [
            "https://hackerrank.example/",
            "HTTPS://HACKERRANK.EXAMPLE",
            "https://hackerrank.example:443",
            "https://HackerRank.Example:443/"
        ] {
            #expect(Account(label: "A", token: "t", baseURLOverride: spelling).serverIdentity == canonical)
        }
    }

    @Test func `server identity keeps different servers apart`() {
        let base = Account(
            label: "A",
            token: "t",
            baseURLOverride: "https://hackerrank.example"
        ).serverIdentity
        for differentServer in [
            "https://other.example",
            "https://hackerrank.example:8443",
            "http://hackerrank.example",
            "https://hackerrank.example/api"
        ] {
            #expect(Account(label: "A", token: "t", baseURLOverride: differentServer).serverIdentity != base)
        }
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

    @Test func `cosmetic base url changes do not point at a different backend`() {
        let original = Account(label: "Work", token: "t", baseURLOverride: "https://eu.test")
        let edited = Account(label: "Work", token: "t", baseURLOverride: "https://EU.TEST:443/", id: original.id)
        #expect(!original.pointsAtDifferentBackend(than: edited))
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
