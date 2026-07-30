//
//  FocusFilter.swift
//  rankbuddy-macos
//
//  A Focus filter (#96) that scopes the whole app to a single HackerRank account while a
//  Focus (e.g. "Work", "Interviewing") is on. A HackerRank account maps 1:1 to an org/token,
//  so scoping to an account is scoping to an org.
//
//  The filter drives the same selection the in-app account switcher uses — `showAllAccounts`
//  + `currentAccountID` on the shared `AccountStore` — rather than introducing a parallel
//  filtering path. Turning the Focus on snapshots the user's pre-Focus selection; turning it
//  off restores exactly that, so the scope is transient and never strands a multi-account
//  user in a single account.
//

import AppIntents
import BuddyAppKit
import Foundation

/// A process-wide weak handle to the app's single live ``AccountStore``, set by the app at
/// launch (`RankBuddyApp`). The Focus-filter intent runs in-process, so when the app is
/// running it drives the *same* store the UI observes — the switch is reflected live. When
/// the app is not running the handle is nil and the intent falls back to a fresh store, whose
/// mutations still persist the selection to UserDefaults for the next launch.
@MainActor
enum SharedAccountStore {
    weak static var shared: AccountStore?

    /// The live store if the app is running, otherwise a fresh store loaded from the Keychain.
    static func resolve() -> AccountStore {
        shared ?? AccountStore.rankBuddy()
    }
}

/// One HackerRank account, surfaced to the system so it can be picked when configuring the
/// Focus filter in System Settings → Focus.
struct AccountFocusEntity: AppEntity, Identifiable {
    /// The account's UUID, as a string (AppEntity ids are stable across launches).
    let id: String
    let displayName: String
    let email: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Account")
    }

    static let defaultQuery = AccountFocusEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        if email.isEmpty {
            DisplayRepresentation(title: "\(displayName)")
        } else {
            DisplayRepresentation(title: "\(displayName)", subtitle: "\(email)")
        }
    }

    init(id: String, displayName: String, email: String) {
        self.id = id
        self.displayName = displayName
        self.email = email
    }

    @MainActor
    init(account: Account) {
        self.init(id: account.id.uuidString, displayName: account.label, email: account.userEmail ?? "")
    }
}

/// Supplies the configured accounts to the Focus-filter picker. The account store is
/// main-actor bound, so each lookup hops to the main actor before reading it.
struct AccountFocusEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AccountFocusEntity] {
        await MainActor.run {
            SharedAccountStore.resolve().accounts
                .filter { identifiers.contains($0.id.uuidString) }
                .map(AccountFocusEntity.init(account:))
        }
    }

    func suggestedEntities() async throws -> [AccountFocusEntity] {
        await MainActor.run {
            SharedAccountStore.resolve().accounts.map(AccountFocusEntity.init(account:))
        }
    }
}

/// Limits the app to one account while a Focus is active. When the Focus turns off the system
/// calls `perform()` again with `account == nil`, which restores the snapshot.
struct ScopeToAccountFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Scope to Account"
    /// Read by the AppIntents framework (Focus settings metadata), not Swift.
    static let description = IntentDescription(
        "Limit RankBuddy to a single HackerRank account while a Focus is on."
    )

    @Parameter(title: "Account")
    var account: AccountFocusEntity?

    var displayRepresentation: DisplayRepresentation {
        if let account {
            DisplayRepresentation(title: "Scoped to \(account.displayName)")
        } else {
            DisplayRepresentation(title: "All accounts")
        }
    }

    private static let savedShowAllKey = "focusFilter.savedShowAllAccounts"
    private static let savedCurrentKey = "focusFilter.savedCurrentAccountID"

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            Self.apply(accountID: account?.id, store: SharedAccountStore.resolve(), defaults: .standard)
        }
        return .result()
    }

    /// Applies the Focus scope to `store`, or restores the pre-Focus selection when `accountID`
    /// is nil (Focus off). Unknown active targets are ignored. The selection is snapshotted on the
    /// first scoping, so a Focus-to-Focus switch (A -> B with no "off" between) still restores the
    /// original selection at the end. Split out of `perform()` so the snapshot/restore logic is
    /// unit-testable without the AppIntents runtime (#96).
    @MainActor
    static func apply(accountID: String?, store: AccountStore, defaults: UserDefaults) {
        if let accountID {
            guard
                let uuid = UUID(uuidString: accountID),
                store.accounts.contains(where: { $0.id == uuid })
            else {
                return
            }

            // Entering a Focus-scoped state: snapshot the pre-Focus selection once, so a
            // later Focus switch (account A -> account B with no "off" between) keeps the
            // original snapshot to restore at the end.
            if defaults.object(forKey: savedShowAllKey) == nil {
                defaults.set(store.showAllAccounts, forKey: savedShowAllKey)
                defaults.set(store.currentAccountID?.uuidString ?? "", forKey: savedCurrentKey)
            }
            store.showAllAccounts = false
            store.currentAccountID = uuid
        } else if defaults.object(forKey: savedShowAllKey) != nil {
            // Focus turned off: restore whatever was selected before it began.
            let savedShowAll = defaults.bool(forKey: savedShowAllKey)
            if let savedID = defaults.string(forKey: savedCurrentKey),
               let uuid = UUID(uuidString: savedID),
               store.accounts.contains(where: { $0.id == uuid }) {
                store.currentAccountID = uuid
            }
            store.showAllAccounts = savedShowAll
            defaults.removeObject(forKey: savedShowAllKey)
            defaults.removeObject(forKey: savedCurrentKey)
        }
    }
}
