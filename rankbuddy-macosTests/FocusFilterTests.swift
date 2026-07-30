//
//  FocusFilterTests.swift
//  rankbuddy-macosTests
//

import BuddyAppKit
import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the Focus filter's snapshot/restore logic (#96): scoping the app to one account
/// while a Focus is on and restoring the exact pre-Focus selection when it turns off. Exercises
/// the pure `ScopeToAccountFocusFilter.apply` helper against an isolated defaults suite, so no
/// AppIntents runtime or shared `UserDefaults.standard` state is involved.
@MainActor
struct FocusFilterTests {
    /// A fresh, empty `UserDefaults` suite unique to each test, so the snapshot keys never leak
    /// between tests or into the app's standard defaults.
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "focusFilter.tests.\(UUID().uuidString)") ?? .standard
    }

    @Test func `scoping to an account narrows the store to that single account`() {
        let work = Account(label: "Work", token: "w")
        let personal = Account(label: "Personal", token: "p")
        let store = AccountStore.rankBuddy(isTesting: true, seed: [work, personal])
        store.showAllAccounts = true
        store.currentAccountID = work.id

        ScopeToAccountFocusFilter.apply(
            accountID: personal.id.uuidString, store: store, defaults: freshDefaults()
        )

        #expect(store.showAllAccounts == false)
        #expect(store.currentAccountID == personal.id)
    }

    @Test func `turning the focus off restores the pre-focus selection`() {
        let work = Account(label: "Work", token: "w")
        let personal = Account(label: "Personal", token: "p")
        let store = AccountStore.rankBuddy(isTesting: true, seed: [work, personal])
        store.showAllAccounts = true
        store.currentAccountID = work.id
        let defaults = freshDefaults()

        ScopeToAccountFocusFilter.apply(accountID: personal.id.uuidString, store: store, defaults: defaults)
        ScopeToAccountFocusFilter.apply(accountID: nil, store: store, defaults: defaults)

        #expect(store.showAllAccounts == true)
        #expect(store.currentAccountID == work.id)
    }

    @Test func `a focus-to-focus switch still restores the original pre-focus selection`() {
        let acctA = Account(label: "A", token: "a")
        let acctB = Account(label: "B", token: "b")
        let acctC = Account(label: "C", token: "c")
        let store = AccountStore.rankBuddy(isTesting: true, seed: [acctA, acctB, acctC])
        store.showAllAccounts = false
        store.currentAccountID = acctA.id
        let defaults = freshDefaults()

        // A -> B -> C with no "off" between: the snapshot is taken once, on the first scoping.
        ScopeToAccountFocusFilter.apply(accountID: acctB.id.uuidString, store: store, defaults: defaults)
        ScopeToAccountFocusFilter.apply(accountID: acctC.id.uuidString, store: store, defaults: defaults)
        #expect(store.currentAccountID == acctC.id)

        ScopeToAccountFocusFilter.apply(accountID: nil, store: store, defaults: defaults)
        #expect(store.showAllAccounts == false)
        #expect(store.currentAccountID == acctA.id)
    }

    @Test func `an unknown account with no snapshot leaves the selection untouched`() {
        let work = Account(label: "Work", token: "w")
        let store = AccountStore.rankBuddy(isTesting: true, seed: [work])
        store.showAllAccounts = true
        store.currentAccountID = work.id

        ScopeToAccountFocusFilter.apply(
            accountID: UUID().uuidString, store: store, defaults: freshDefaults()
        )

        #expect(store.showAllAccounts == true)
        #expect(store.currentAccountID == work.id)
    }

    @Test(arguments: [UUID().uuidString, "not-a-uuid"])
    func `an invalid active target does not turn an existing focus off`(_ invalidID: String) {
        let work = Account(label: "Work", token: "w")
        let personal = Account(label: "Personal", token: "p")
        let store = AccountStore.rankBuddy(isTesting: true, seed: [work, personal])
        store.showAllAccounts = true
        store.currentAccountID = work.id
        let defaults = freshDefaults()

        ScopeToAccountFocusFilter.apply(
            accountID: personal.id.uuidString,
            store: store,
            defaults: defaults
        )
        ScopeToAccountFocusFilter.apply(accountID: invalidID, store: store, defaults: defaults)

        #expect(store.showAllAccounts == false)
        #expect(store.currentAccountID == personal.id)

        ScopeToAccountFocusFilter.apply(accountID: nil, store: store, defaults: defaults)
        #expect(store.showAllAccounts == true)
        #expect(store.currentAccountID == work.id)
    }
}
