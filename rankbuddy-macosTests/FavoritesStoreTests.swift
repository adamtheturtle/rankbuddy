//
//  FavoritesStoreTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the account-aware favourites store (#25): toggling, account scoping,
/// persistence across launches, and pruning when an account is removed.
@MainActor
struct FavoritesStoreTests {
    /// A fresh, isolated `UserDefaults` so tests never touch the real domain or each other.
    private func makeDefaults(_ name: String) -> UserDefaults {
        let suite = "favorites.tests.\(name)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func ref(
        _ account: String = "acc1",
        _ collection: FavoriteCollection = .tests,
        _ item: String = "t1",
        _ title: String = "Backend Screen"
    ) -> FavoriteRef {
        FavoriteRef(accountID: account, collection: collection, itemID: item, title: title)
    }

    @Test func `toggling adds then removes a favourite`() {
        let store = FavoritesStore(defaults: makeDefaults(#function))
        let item = ref()

        #expect(!store.isFavorite(collection: .tests, accountID: "acc1", itemID: "t1"))
        #expect(store.toggle(item) == true)
        #expect(store.isFavorite(collection: .tests, accountID: "acc1", itemID: "t1"))
        #expect(store.toggle(item) == false)
        #expect(!store.isFavorite(collection: .tests, accountID: "acc1", itemID: "t1"))
    }

    @Test func `toggling the same id twice does not duplicate`() {
        let store = FavoritesStore(defaults: makeDefaults(#function))
        store.toggle(ref())
        store.toggle(ref("acc1", .tests, "t1", "Renamed but same id"))
        // The second toggle matches by id and removes, leaving none.
        #expect(store.favorites.isEmpty)
    }

    @Test func `favourites are scoped by account and collection`() {
        let store = FavoritesStore(defaults: makeDefaults(#function))
        store.toggle(ref("acc1", .tests, "t1", "T1"))
        store.toggle(ref("acc1", .questions, "q1", "Q1"))
        store.toggle(ref("acc2", .tests, "t2", "T2"))

        #expect(store.favorites(accountID: "acc1").count == 2)
        #expect(store.favorites(accountID: "acc1", collection: .tests).map(\.itemID) == ["t1"])
        #expect(store.favorites(accountID: "acc2", collection: .tests).map(\.itemID) == ["t2"])
        #expect(!store.isFavorite(collection: .tests, accountID: "acc2", itemID: "t1"))
    }

    @Test func `favourites can be read across an account scope`() {
        let store = FavoritesStore(defaults: makeDefaults(#function))
        store.replace(with: [
            ref("acc1", .tests, "t1", "One"),
            ref("removed", .tests, "t2", "Removed"),
            ref("acc2", .questions, "q1", "Two")
        ])

        let scoped = store.favorites(accountIDs: ["acc1", "acc2"])

        #expect(scoped.map(\.itemID) == ["q1", "t1"])
    }

    @Test func `most recently added favourite comes first`() {
        let store = FavoritesStore(defaults: makeDefaults(#function))
        store.toggle(ref("acc1", .tests, "t1", "First"))
        store.toggle(ref("acc1", .tests, "t2", "Second"))
        #expect(store.favorites(accountID: "acc1", collection: .tests).map(\.itemID) == ["t2", "t1"])
    }

    @Test func `favourites persist across store instances`() {
        let defaults = makeDefaults(#function)
        let first = FavoritesStore(defaults: defaults)
        first.toggle(ref("acc1", .interviews, "i1", "Pairing"))

        let second = FavoritesStore(defaults: defaults)
        #expect(second.isFavorite(collection: .interviews, accountID: "acc1", itemID: "i1"))
    }

    @Test func `corrupt favourites are quarantined until explicitly reset`() {
        let defaults = makeDefaults(#function)
        let corrupt = Data("not json".utf8)
        defaults.set(corrupt, forKey: FavoritesStore.storageKey)
        let store = FavoritesStore(defaults: defaults)

        #expect(store.hasUnreadableData)
        #expect(store.showsRecoveryAlert)
        #expect(defaults.data(forKey: FavoritesStore.recoveryKey) == corrupt)
        store.add(ref())
        #expect(defaults.data(forKey: FavoritesStore.storageKey) == corrupt)

        store.resetUnreadableData()
        #expect(!store.hasUnreadableData)
        store.add(ref())
        #expect(store.favorites == [ref()])
        #expect(defaults.data(forKey: FavoritesStore.recoveryKey) == corrupt)
    }

    @Test func `a testing store ignores persisted favourites`() {
        let defaults = makeDefaults(#function)
        FavoritesStore(defaults: defaults).toggle(ref())
        // A demo/test store must start clean and not read the real domain.
        let testing = FavoritesStore(defaults: defaults, isTesting: true)
        #expect(testing.favorites.isEmpty)
    }

    @Test func `pruning drops favourites for removed accounts`() {
        let store = FavoritesStore(defaults: makeDefaults(#function))
        store.toggle(ref("acc1", .tests, "t1", "Keep"))
        store.toggle(ref("acc2", .tests, "t2", "Drop"))

        store.prune(toAccountIDs: ["acc1"])
        #expect(store.favorites.map(\.itemID) == ["t1"])
        #expect(!store.isFavorite(collection: .tests, accountID: "acc2", itemID: "t2"))
    }

    @Test func `pruning is a no-op when every account still exists`() {
        let store = FavoritesStore(defaults: makeDefaults(#function))
        store.toggle(ref("acc1", .tests, "t1", "Keep"))
        store.prune(toAccountIDs: ["acc1", "acc2"])
        #expect(store.favorites.count == 1)
    }

    @Test func `the ref id combines account, collection, and item`() {
        #expect(ref("a", .questions, "q9").id == "a|questions|q9")
    }

    @Test func `reload identity cannot collide around pipe characters`() {
        let first = FavoritesReloadIdentity(ids: ["a", "b|c"])
        let second = FavoritesReloadIdentity(ids: ["a|b", "c"])

        #expect(first != second)
        #expect(
            FavoritesReloadIdentity(ids: ["second", "first"])
                == FavoritesReloadIdentity(ids: ["first", "second"])
        )
    }

    @Test func `add pins an absent favourite`() {
        let store = FavoritesStore(defaults: makeDefaults(#function))
        store.add(ref())
        #expect(store.isFavorite(collection: .tests, accountID: "acc1", itemID: "t1"))
    }

    @Test func `add is idempotent and never un-favourites`() {
        let store = FavoritesStore(defaults: makeDefaults(#function))
        store.add(ref())
        // Dropping an already-pinned row again must leave it pinned, unlike toggle (#89).
        store.add(ref("acc1", .tests, "t1", "Same id, new title"))
        #expect(store.favorites.count == 1)
        #expect(store.isFavorite(collection: .tests, accountID: "acc1", itemID: "t1"))
    }

    @Test func `undo restores favourite toggle state`() {
        let store = FavoritesStore(defaults: makeDefaults(#function))
        let undoManager = UndoManager()
        let item = ref()

        store.toggle(item, undoManager: undoManager)
        #expect(store.isFavorite(collection: .tests, accountID: "acc1", itemID: "t1"))

        undoManager.undo()
        #expect(!store.isFavorite(collection: .tests, accountID: "acc1", itemID: "t1"))

        undoManager.redo()
        #expect(store.isFavorite(collection: .tests, accountID: "acc1", itemID: "t1"))
    }

    @Test func `undo restores favourite reorder`() {
        let store = FavoritesStore(defaults: makeDefaults(#function))
        let undoManager = UndoManager()
        store.add(ref("acc1", .tests, "a", "A"))
        store.add(ref("acc1", .tests, "b", "B"))

        store.replace(with: [ref("acc1", .tests, "b", "B"), ref("acc1", .tests, "a", "A")],
                      undoManager: undoManager, actionName: "Reorder Favourites")
        #expect(store.favorites.map(\.itemID) == ["b", "a"])

        undoManager.undo()
        #expect(store.favorites.map(\.itemID) == ["a", "b"])
    }
}
