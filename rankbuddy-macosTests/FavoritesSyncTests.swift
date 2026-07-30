//
//  FavoritesSyncTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the favourites iCloud sync coordinator (#22), using a fake key-value store so
/// the merge/deletion/availability rules are exercised without iCloud.
@MainActor
struct FavoritesSyncTests {
    /// An in-memory `KeyValueSyncStore` whose availability and external-change delivery are
    /// driven by the test.
    private final class FakeStore: KeyValueSyncStore {
        var isAvailable: Bool
        var onExternalChange: (() -> Void)?
        var onAvailabilityChange: (() -> Void)?
        private var storage: [String: Data] = [:]
        private(set) var writes = 0

        init(isAvailable: Bool = true) {
            self.isAvailable = isAvailable
        }

        func data(forKey key: String) -> Data? {
            storage[key]
        }

        func setData(_ data: Data?, forKey key: String) {
            storage[key] = data
            writes += 1
        }

        @discardableResult func synchronize() -> Bool {
            true
        }

        /// Simulates another device writing the value, then delivering the external change.
        func remoteWrite(_ refs: [FavoriteRef]) {
            storage[FavoritesSyncCoordinator.key] = try? JSONEncoder().encode(refs)
            onExternalChange?()
        }

        func remoteDelete() {
            storage[FavoritesSyncCoordinator.key] = nil
            onExternalChange?()
        }

        func remoteWriteMalformed() {
            storage[FavoritesSyncCoordinator.key] = Data("not json".utf8)
            onExternalChange?()
        }

        func becomeAvailable(with refs: [FavoriteRef]) {
            storage[FavoritesSyncCoordinator.key] = try? JSONEncoder().encode(refs)
            isAvailable = true
            onAvailabilityChange?()
        }
    }

    private func ref(_ item: String, _ collection: FavoriteCollection = .tests) -> FavoriteRef {
        FavoriteRef(accountID: "acc1", collection: collection, itemID: item, title: item.uppercased())
    }

    private func defaults(_ name: String) -> UserDefaults {
        let suite = "favsync.tests.\(name)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Starts a coordinator and keeps it alive for the duration of `body` (its change hooks
    /// capture `self` weakly, mirroring the app where `@State` retains it).
    private func withCoordinator(
        _ favorites: FavoritesStore,
        _ store: FakeStore,
        _ body: (FavoritesSyncCoordinator) -> Void
    ) {
        let coordinator = FavoritesSyncCoordinator(favorites: favorites, store: store)
        coordinator.start()
        withExtendedLifetime(coordinator) { body(coordinator) }
    }

    @Test func `a local change is pushed to the store`() {
        let favorites = FavoritesStore(defaults: defaults(#function), isTesting: true)
        withCoordinator(favorites, FakeStore()) { _ in
            favorites.toggle(ref("t1"))
            #expect(favorites.favorites.count == 1)
        }
    }

    @Test func `an external change is adopted locally`() {
        let favorites = FavoritesStore(defaults: defaults(#function), isTesting: true)
        let store = FakeStore()
        withCoordinator(favorites, store) { _ in
            store.remoteWrite([ref("t1"), ref("q1", .questions)])
            #expect(favorites.favorites.map(\.itemID) == ["t1", "q1"])
        }
    }

    @Test func `adopting a remote change does not echo back out`() {
        let favorites = FavoritesStore(defaults: defaults(#function), isTesting: true)
        let store = FakeStore()
        withCoordinator(favorites, store) { _ in
            let writesBefore = store.writes
            store.remoteWrite([ref("t1")])
            // The adopt must not trigger a push back to the store (no re-entrant write).
            #expect(store.writes == writesBefore)
        }
    }

    @Test func `a remote deletion propagates by adopting the smaller set`() {
        let favorites = FavoritesStore(defaults: defaults(#function), isTesting: true)
        let store = FakeStore()
        withCoordinator(favorites, store) { _ in
            store.remoteWrite([ref("t1"), ref("t2")])
            #expect(favorites.favorites.count == 2)
            store.remoteWrite([ref("t1")]) // t2 removed elsewhere
            #expect(favorites.favorites.map(\.itemID) == ["t1"])
        }
    }

    @Test func `deleting the remote key clears local favourites`() {
        let favorites = FavoritesStore(defaults: defaults(#function), isTesting: true)
        let store = FakeStore()
        withCoordinator(favorites, store) { _ in
            store.remoteWrite([ref("t1")])
            #expect(favorites.favorites.count == 1)

            store.remoteDelete()

            #expect(favorites.favorites.isEmpty)
        }
    }

    @Test func `malformed remote data is replaced with normalized local state`() {
        let favorites = FavoritesStore(defaults: defaults(#function), isTesting: true)
        let store = FakeStore()
        withCoordinator(favorites, store) { _ in
            favorites.toggle(ref("local"))
            let writesBefore = store.writes

            store.remoteWriteMalformed()

            let repaired = store.data(forKey: FavoritesSyncCoordinator.key)
                .flatMap { try? JSONDecoder().decode([FavoriteRef].self, from: $0) }
            #expect(repaired?.map(\.itemID) == ["local"])
            #expect(store.writes == writesBefore + 1)
        }
    }

    @Test func `a local toggle writes the encoded set to the store`() {
        let favorites = FavoritesStore(defaults: defaults(#function), isTesting: true)
        let store = FakeStore()
        withCoordinator(favorites, store) { _ in
            favorites.toggle(ref("t1"))
            let data = store.data(forKey: FavoritesSyncCoordinator.key)
            let decoded = try? JSONDecoder().decode([FavoriteRef].self, from: data ?? Data())
            #expect(decoded?.map(\.itemID) == ["t1"])
        }
    }

    @Test func `an unavailable store leaves everything local and inert`() {
        let favorites = FavoritesStore(defaults: defaults(#function), isTesting: true)
        let store = FakeStore(isAvailable: false)
        withCoordinator(favorites, store) { coordinator in
            #expect(!coordinator.isEnabled)
            favorites.toggle(ref("t1"))
            // No push when unavailable; local favourites still work.
            #expect(store.data(forKey: FavoritesSyncCoordinator.key) == nil)
            #expect(favorites.isFavorite(collection: .tests, accountID: "acc1", itemID: "t1"))
        }
    }

    @Test func `sync activates when the store becomes available later`() {
        let favorites = FavoritesStore(defaults: defaults(#function), isTesting: true)
        let store = FakeStore(isAvailable: false)
        withCoordinator(favorites, store) { coordinator in
            #expect(!coordinator.isEnabled)

            store.becomeAvailable(with: [ref("remote")])

            #expect(coordinator.isEnabled)
            #expect(favorites.favorites.map(\.itemID) == ["remote"])
        }
    }

    @Test func `start adopts an existing remote value`() {
        let favorites = FavoritesStore(defaults: defaults(#function), isTesting: true)
        let store = FakeStore()
        store.setData(try? JSONEncoder().encode([ref("seed")]), forKey: FavoritesSyncCoordinator.key)
        withCoordinator(favorites, store) { _ in
            #expect(favorites.favorites.map(\.itemID) == ["seed"])
        }
    }
}
