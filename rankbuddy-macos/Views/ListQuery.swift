import BuddyAppKit
import Foundation

/// Pure list shaping for `LoadableList`: the search + date-range filter applied before sorting
/// (#19). Factored out of the view so the list stays within the size gates and the filtering
/// is reusable.
enum ListQuery {
    /// Filters by the free-text query (case-insensitive substring over `searchableText`) and,
    /// when a `date` accessor is supplied, by the named date range.
    static func filtered<Item>(
        _ items: [Item],
        query: String,
        searchableText: (Item) -> String,
        date: ((Item) -> Date?)?,
        dateRange: String?
    ) -> [Item] {
        var result = items
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result = result.filter { searchableText($0).localizedCaseInsensitiveContains(trimmed) }
        }

        if let date {
            result = DateRangeFilter.apply(result, range: dateRange, date: date)
        }

        return result
    }

    /// The `UserDefaults` key the chosen date filter persists under (#19), or `nil` when the
    /// list has no restoration key (persistence off).
    static func filterKey(_ restorationKey: String?) -> String? {
        restorationKey.map { "filter.\($0)" }
    }

    /// The saved date range for `key`, ignoring any stale/unknown value.
    static func restoredRange(key: String?, defaults: UserDefaults = .standard) -> String? {
        guard let key else { return nil }

        let saved = defaults.string(forKey: key)
        return NamedDateRange.options.contains(saved ?? "") ? saved : nil
    }

    /// Persists the chosen date range under `key`, clearing it when no range is selected.
    static func persistRange(_ range: String?, key: String?, defaults: UserDefaults = .standard) {
        guard let key else { return }

        if let range {
            defaults.set(range, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
