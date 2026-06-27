//
//  FavoritesSync.swift
//  rankbuddy-macos
//

import BuddyAppKit
import Foundation

/// A minimal key-value sync backend, abstracted so the favourites sync logic is testable
/// without iCloud (#22). The app implementation adapts buddy-kit's `CloudSyncStore`.
@MainActor
protocol KeyValueSyncStore: AnyObject {
    /// Whether the synchronized store is actually usable — gated on the real iCloud KVS
    /// capability, not merely on an Apple ID being signed in.
    var isAvailable: Bool { get }
    /// Invoked when the store's value changes externally (another device wrote it).
    var onExternalChange: (() -> Void)? { get set }
    func data(forKey key: String) -> Data?
    func setData(_ data: Data?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

/// Adapts buddy-kit's shared `CloudSyncStore` to `KeyValueSyncStore` (#22).
///
/// `CloudSyncStore.isAvailable` gates on the actual `ubiquity-kvstore-identifier` entitlement
/// (via `SecTask`), so a build without it reports unavailable and the coordinator stays inert.
/// External changes arrive as `CloudSyncStore.didChangeExternally` notifications; this bridges
/// the one for our key onto the protocol's `onExternalChange` closure.
@MainActor
final class CloudSyncKeyValueStore: KeyValueSyncStore {
    var onExternalChange: (() -> Void)?

    private let cloud = CloudSyncStore.shared
    private let key: String
    private var observer: Task<Void, Never>?

    init(key: String) {
        self.key = key
        cloud.start()
        observer = Task { @MainActor [weak self] in
            for await note in NotificationCenter.default.notifications(named: CloudSyncStore.didChangeExternally) {
                guard let self, (note.userInfo?["key"] as? String) == key else { continue }

                onExternalChange?()
            }
        }
    }

    deinit {
        observer?.cancel()
    }

    var isAvailable: Bool {
        cloud.isAvailable
    }

    func data(forKey key: String) -> Data? {
        cloud.data(forKey: key)
    }

    func setData(_ data: Data?, forKey key: String) {
        // Favourites are always written as a full (possibly empty) array, never nil.
        guard let data else { return }

        cloud.mirror(data, forKey: key)
    }

    @discardableResult func synchronize() -> Bool {
        // CloudSyncStore synchronizes internally on start and write; nothing extra to do.
        true
    }
}

/// Mirrors the local `FavoritesStore` to/from a key-value sync store (#22).
///
/// Favourites are non-secret user state (no tokens or API payloads), synced as the whole
/// `[FavoriteRef]` JSON blob under one key. The merge rule is **whole-set last-writer-wins**:
/// every local change is pushed immediately, and an incoming external change is adopted
/// wholesale — which propagates additions *and* deletions deterministically (buddy-kit's
/// `CloudSyncMerge` is union-only and wouldn't propagate deletions). An `isAdopting` guard
/// stops an adopted change from echoing straight back. When the store is unavailable (no iCloud
/// entitlement/account) the coordinator does nothing, so the app works unchanged locally.
@MainActor
final class FavoritesSyncCoordinator {
    /// The shared key, identical to the local `FavoritesStore` storage key so a future
    /// migration stays trivial.
    static let key = "rankbuddy.favorites"

    private let favorites: FavoritesStore
    private let store: KeyValueSyncStore
    private var isAdopting = false

    init(favorites: FavoritesStore, store: KeyValueSyncStore) {
        self.favorites = favorites
        self.store = store
    }

    /// Whether sync is active (the backing store is usable).
    var isEnabled: Bool {
        store.isAvailable
    }

    /// Begins syncing: adopts any existing remote value, then mirrors changes both ways. A
    /// no-op when the store is unavailable.
    func start() {
        guard store.isAvailable else { return }

        adoptRemote()
        store.onExternalChange = { [weak self] in self?.adoptRemote() }
        favorites.onChange = { [weak self] in self?.pushLocal() }
        store.synchronize()
    }

    /// Adopts the remote favourites wholesale (last-writer-wins), guarded so it doesn't echo
    /// back out as a local change.
    func adoptRemote() {
        guard let data = store.data(forKey: Self.key),
              let remote = try? JSONDecoder().decode([FavoriteRef].self, from: data)
        else { return }

        isAdopting = true
        defer { isAdopting = false }
        favorites.replace(with: remote)
    }

    /// Pushes the current local favourites to the store, unless this change came from adopting
    /// a remote one or the store is unavailable.
    func pushLocal() {
        guard !isAdopting, store.isAvailable,
              let data = try? JSONEncoder().encode(favorites.favorites)
        else { return }

        store.setData(data, forKey: Self.key)
        store.synchronize()
    }
}
