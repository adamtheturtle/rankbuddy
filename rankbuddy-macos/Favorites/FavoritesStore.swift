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
    private let defaults: UserDefaults
    private let storageKey = "rankbuddy.favorites"

    /// The favourites in insertion order (oldest first); display surfaces reverse to show
    /// the most-recently-added first.
    private(set) var favorites: [FavoriteRef]

    /// - Parameters:
    ///   - defaults: the backing store; injectable so tests stay isolated.
    ///   - isTesting: when true the store starts empty and never reads existing defaults, so
    ///     demo mode and tests don't pick up (or pollute) real favourites.
    init(defaults: UserDefaults = .standard, isTesting: Bool = false) {
        self.defaults = defaults
        if isTesting {
            favorites = []
        } else if let data = defaults.data(forKey: storageKey),
                  let decoded = try? JSONDecoder().decode([FavoriteRef].self, from: data) {
            favorites = decoded
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

    /// Adds the item when absent, removes it when present. Returns the resulting state.
    @discardableResult
    func toggle(_ ref: FavoriteRef) -> Bool {
        if let index = favorites.firstIndex(where: { $0.id == ref.id }) {
            favorites.remove(at: index)
            persist()
            return false
        }
        favorites.append(ref)
        persist()
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

    /// Drops every favourite whose account is no longer configured, so a removed account
    /// leaves no dangling navigation entries (#25). No-op when nothing changes.
    func prune(toAccountIDs ids: Set<String>) {
        let kept = favorites.filter { ids.contains($0.accountID) }
        guard kept.count != favorites.count else { return }

        favorites = kept
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }

        defaults.set(data, forKey: storageKey)
    }

    /// The favourite-toggle state for a row's context menu, or `nil` when there is no current
    /// account (nothing to scope the favourite to). The toggle adds/removes the item.
    func menuState(
        accountID: UUID?,
        collection: FavoriteCollection,
        itemID: String,
        title: String
    ) -> (isFavorite: Bool, toggle: () -> Void)? {
        guard let accountID else { return nil }

        let ref = FavoriteRef(
            accountID: accountID.uuidString,
            collection: collection,
            itemID: itemID,
            title: title
        )
        return (isFavorite(collection: collection, accountID: ref.accountID, itemID: itemID), { self.toggle(ref) })
    }
}
