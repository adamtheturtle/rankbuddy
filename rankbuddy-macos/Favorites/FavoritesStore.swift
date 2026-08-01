//
//  FavoritesStore.swift
//  rankbuddy-macos
//

import Foundation
import Observation

/// A favouritable top-level collection (#25). Raw values match the restoration-key
/// collection segment and `SidebarSection`, so opening a favourite can drive the shared
/// persisted selection directly.
nonisolated enum FavoriteCollection: String, Codable, Hashable, CaseIterable {
    case tests
    case questions
    case interviews

    /// The sidebar section this collection routes to.
    var section: SidebarSection {
        switch self {
        case .tests: .tests
        case .questions: .questions
        case .interviews: .interviews
        }
    }

    /// The SF Symbol shown for the collection in favourites surfaces.
    var systemImage: String {
        section.systemImage
    }

    /// The free-text palette category label for a favourite of this collection.
    var paletteCategory: String {
        "Favourite \(section.title)"
    }
}

/// A reference to a favourited item: just enough to display it and route back to it, with
/// no secret or heavy payload, so it is safe to persist and later sync (#22/#25).
nonisolated struct FavoriteRef: Codable, Hashable, Identifiable {
    /// The account the item belongs to (favourites are account-scoped).
    let accountID: String
    /// Which collection the item is in.
    let collection: FavoriteCollection
    /// The item's stable API identifier.
    let itemID: String
    /// A human-readable title for the favourites/palette surfaces.
    var title: String

    /// A stable identity combining account, collection, and item.
    var id: String {
        "\(accountID)|\(collection.rawValue)|\(itemID)"
    }
}

/// Account-aware favourites for the read-only collections (#25).
///
/// Persists a small list of `FavoriteRef`s as JSON in `UserDefaults` — non-secret state,
/// deliberately kept lightweight and serialisable so it is suitable for later iCloud sync
/// (#22). MainActor-isolated; observed by the views that toggle and display favourites.
@Observable
@MainActor
final class FavoritesStore {
    static let storageKey = "rankbuddy.favorites"
    static let recoveryKey = "rankbuddy.favorites.unreadable-backup"
    static let modifiedAtKey = "rankbuddy.favorites.modifiedAt"
    private let defaults: UserDefaults

    /// The favourites in insertion order (oldest first); display surfaces reverse to show
    /// the most-recently-added first.
    private(set) var favorites: [FavoriteRef]
    private(set) var modifiedAt: Date
    private(set) var hasUnreadableData = false
    var showsRecoveryAlert = false

    /// Called after any local mutation persists, so a sync coordinator can mirror the change
    /// (#22). Not part of the observable surface.
    @ObservationIgnored var onChange: (() -> Void)?

    /// - Parameters:
    ///   - defaults: the backing store; injectable so tests stay isolated.
    ///   - isTesting: when true the store starts empty and never reads existing defaults, so
    ///     demo mode and tests don't pick up (or pollute) real favourites.
    init(defaults: UserDefaults = .standard, isTesting: Bool = false) {
        self.defaults = defaults
        modifiedAt = defaults.object(forKey: Self.modifiedAtKey) as? Date ?? .distantPast
        if isTesting {
            favorites = []
        } else if let data = defaults.data(forKey: Self.storageKey),
                  let decoded = try? JSONDecoder().decode([FavoriteRef].self, from: data) {
            let normalized = Self.normalized(decoded)
            favorites = normalized
            if normalized != decoded, let repaired = try? JSONEncoder().encode(normalized) {
                defaults.set(repaired, forKey: Self.storageKey)
            }
        } else if let data = defaults.data(forKey: Self.storageKey) {
            favorites = []
            hasUnreadableData = true
            showsRecoveryAlert = true
            if defaults.data(forKey: Self.recoveryKey) == nil {
                defaults.set(data, forKey: Self.recoveryKey)
            }
        } else {
            favorites = []
        }
    }

    /// Whether the given item is currently favourited.
    func isFavorite(collection: FavoriteCollection, accountID: String, itemID: String) -> Bool {
        favorites.contains {
            $0.collection == collection && $0.accountID == accountID && $0.itemID == itemID
        }
    }

    /// Pins the item if it isn't already favourited; a no-op when it is. Unlike `toggle`, a
    /// repeated add never removes — the right semantics for drag-to-pin (#89), where dropping an
    /// already-pinned row should leave it pinned rather than silently un-favourite it.
    func add(_ ref: FavoriteRef, undoManager: UndoManager? = nil) {
        guard !hasUnreadableData else { return }
        guard !favorites.contains(where: { $0.id == ref.id }) else { return }

        replace(with: favorites + [ref], undoManager: undoManager, actionName: "Add Favourite")
    }

    /// Refreshes display metadata for already-favourited items without adding new favourites or
    /// changing their order.
    func refreshMetadata(from refs: [FavoriteRef]) {
        guard !hasUnreadableData else { return }

        let titles = Dictionary(refs.map { ($0.id, $0.title) }, uniquingKeysWith: { _, newest in newest })
        let refreshed = favorites.map { favorite in
            guard let title = titles[favorite.id], title != favorite.title else { return favorite }

            return FavoriteRef(
                accountID: favorite.accountID,
                collection: favorite.collection,
                itemID: favorite.itemID,
                title: title
            )
        }
        replace(with: refreshed)
    }

    /// Adds the item when absent, removes it when present. Returns the resulting state.
    @discardableResult
    func toggle(_ ref: FavoriteRef, undoManager: UndoManager? = nil) -> Bool {
        guard !hasUnreadableData else {
            return isFavorite(collection: ref.collection, accountID: ref.accountID, itemID: ref.itemID)
        }

        if let index = favorites.firstIndex(where: { $0.id == ref.id }) {
            var updated = favorites
            updated.remove(at: index)
            replace(with: updated, undoManager: undoManager, actionName: "Remove Favourite")
            return false
        }
        replace(with: favorites + [ref], undoManager: undoManager, actionName: "Add Favourite")
        return true
    }

    /// The favourites for one account and collection, most-recently-added first.
    func favorites(accountID: String, collection: FavoriteCollection) -> [FavoriteRef] {
        favorites.filter { $0.accountID == accountID && $0.collection == collection }.reversed()
    }

    /// All of an account's favourites across every collection, most-recently-added first.
    func favorites(accountID: String) -> [FavoriteRef] {
        favorites.filter { $0.accountID == accountID }.reversed()
    }

    /// All favourites belonging to the selected account scope, most-recently-added first.
    func favorites(accountIDs: Set<String>) -> [FavoriteRef] {
        favorites.filter { accountIDs.contains($0.accountID) }.reversed()
    }

    /// Drops every favourite whose account is no longer configured, so a removed account
    /// leaves no dangling navigation entries (#25). No-op when nothing changes.
    func prune(toAccountIDs ids: Set<String>) {
        guard !hasUnreadableData else { return }

        let kept = favorites.filter { ids.contains($0.accountID) }
        guard kept.count != favorites.count else { return }

        favorites = kept
        persist()
    }

    /// Replaces the whole set, e.g. when adopting an incoming iCloud change (#22). No-op when
    /// the set is unchanged, so it doesn't churn observers or re-trigger a sync.
    func replace(
        with refs: [FavoriteRef],
        undoManager: UndoManager? = nil,
        actionName: String = "Change Favourites"
    ) {
        guard !hasUnreadableData else { return }

        let normalized = Self.normalized(refs)
        let previous = favorites
        guard normalized != previous else { return }

        favorites = normalized
        persist()
        registerUndo(previous, undoManager: undoManager, actionName: actionName)
    }

    /// Adopts a versioned remote snapshot without giving it a new local modification date.
    func adopt(_ refs: [FavoriteRef], modifiedAt remoteDate: Date) {
        guard !hasUnreadableData else { return }

        let normalized = Self.normalized(refs)
        guard normalized != favorites || remoteDate != modifiedAt else { return }

        favorites = normalized
        persist(modifiedAt: remoteDate)
    }

    /// Keeps the last occurrence of each identity, matching the store's newest-wins ordering.
    private static func normalized(_ refs: [FavoriteRef]) -> [FavoriteRef] {
        var seen = Set<String>()
        let newestUnique = refs.reversed().filter { seen.insert($0.id).inserted }
        return Array(newestUnique.reversed())
    }

    private func registerUndo(_ previous: [FavoriteRef], undoManager: UndoManager?, actionName: String) {
        guard let undoManager else { return }

        undoManager.registerUndo(withTarget: self) { store in
            store.replace(with: previous, undoManager: undoManager, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    private func persist(modifiedAt date: Date = Date()) {
        guard !hasUnreadableData else { return }
        guard let data = try? JSONEncoder().encode(favorites) else { return }

        modifiedAt = date
        defaults.set(data, forKey: Self.storageKey)
        defaults.set(date, forKey: Self.modifiedAtKey)
        onChange?()
    }

    /// Explicitly abandons the quarantined payload and starts a new empty favourites list.
    func resetUnreadableData() {
        guard hasUnreadableData else { return }

        favorites = []
        hasUnreadableData = false
        showsRecoveryAlert = false
        defaults.removeObject(forKey: Self.recoveryKey)
        persist()
    }

    /// The favourite-toggle state for a row's context menu, or `nil` when there is no current
    /// account (nothing to scope the favourite to). The toggle adds/removes the item.
    func menuState(
        accountID: UUID?,
        collection: FavoriteCollection,
        itemID: String,
        title: String,
        undoManager: UndoManager? = nil
    ) -> (isFavorite: Bool, toggle: () -> Void)? {
        guard let accountID else { return nil }

        let ref = FavoriteRef(
            accountID: accountID.uuidString,
            collection: collection,
            itemID: itemID,
            title: title
        )
        return (
            isFavorite(collection: collection, accountID: ref.accountID, itemID: itemID),
            { self.toggle(ref, undoManager: undoManager) }
        )
    }
}
