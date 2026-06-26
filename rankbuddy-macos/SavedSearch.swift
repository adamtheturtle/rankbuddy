import Foundation

/// A named, reusable combination of a list's free-text query and date-range filter (#25),
/// so a recruiter can re-run "last 7 days, failed" without re-entering it.
///
/// Sort is deliberately not captured: it's a presentation preference already persisted on
/// its own, whereas a saved search is about *which* rows are shown.
nonisolated struct SavedSearch: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    /// The free-text query, or empty for none.
    var query: String
    /// The selected date-range option (one of `NamedDateRange.options`), or `nil`.
    var dateRange: String?

    init(name: String, query: String, dateRange: String?, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.query = query
        self.dateRange = dateRange
    }

    /// Whether this captures any constraint at all — an empty query and no range would
    /// save nothing useful, so the UI refuses to create one.
    var isEmpty: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && dateRange == nil
    }
}

/// Per-list persistence for saved searches, scoped by the list's restoration key so each
/// account/collection keeps its own (mirrors how favourites and filters are scoped).
enum SavedSearchStore {
    /// The `UserDefaults` key backing a list's saved searches.
    static func defaultsKey(for restorationKey: String) -> String {
        "savedsearch.\(restorationKey)"
    }

    /// Loads the saved searches for a list, or an empty array when none/unreadable.
    static func load(restorationKey: String, defaults: UserDefaults = .standard) -> [SavedSearch] {
        guard let data = defaults.data(forKey: defaultsKey(for: restorationKey)),
              let searches = try? JSONDecoder().decode([SavedSearch].self, from: data)
        else { return [] }

        return searches
    }

    /// Persists the saved searches for a list, removing the key entirely when empty.
    static func save(_ searches: [SavedSearch], restorationKey: String, defaults: UserDefaults = .standard) {
        let key = defaultsKey(for: restorationKey)
        guard !searches.isEmpty, let data = try? JSONEncoder().encode(searches) else {
            defaults.removeObject(forKey: key)
            return
        }

        defaults.set(data, forKey: key)
    }
}
