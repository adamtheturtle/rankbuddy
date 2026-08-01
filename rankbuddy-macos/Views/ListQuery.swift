//
//  ListQuery.swift
//  rankbuddy-macos
//

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
        dateRange: String?,
        now: Date = Date()
    ) -> [Item] {
        var result = items
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result = result.filter { searchableText($0).localizedCaseInsensitiveContains(trimmed) }
        }

        if let date {
            result = DateRangeFilter.apply(result, range: dateRange, now: now, date: date)
        }

        return result
    }

    /// Whether `item` satisfies the active facet selection (#55): for every facet with a
    /// non-empty chosen set, at least one of the item's values for that facet must be chosen
    /// (AND across facets, OR within a facet). Facets with no selection impose no constraint.
    static func matchesFacets<Item>(
        _ item: Item,
        facets: [ListFacet<Item>],
        selected: [String: Set<String>]
    ) -> Bool {
        for facet in facets {
            guard let chosen = selected[facet.id], !chosen.isEmpty else { continue }

            let normalizedChosen = Set(chosen.map(normalizedFacetValue))
            let normalizedValues = Set(facet.values(item).map(normalizedFacetValue))
            if normalizedValues.isDisjoint(with: normalizedChosen) {
                return false
            }
        }
        return true
    }

    /// The distinct, non-empty values present for `facet` across `items`, sorted for display —
    /// the options the facet's dropdown offers (#55).
    static func facetOptions<Item>(_ facet: ListFacet<Item>, in items: [Item]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for item in items {
            for value in facet.values(item) {
                let displayValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = normalizedFacetValue(displayValue)
                if !displayValue.isEmpty, seen.insert(normalized).inserted {
                    ordered.append(displayValue)
                }
            }
        }
        return ordered.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Comparison key shared by facet option identity and filtering. Case folding matches the
    /// localized, case-insensitive semantics used by list text search while retaining one backend
    /// spelling for display.
    nonisolated static func normalizedFacetValue(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .caseInsensitive, locale: .current)
    }

    /// The `UserDefaults` key the chosen date filter persists under (#19), or `nil` when the
    /// list has no restoration key (persistence off).
    static func filterKey(_ restorationKey: String?) -> String? {
        restorationKey.map { "filter.\($0)" }
    }

    /// The `UserDefaults` key the active facet selection persists under (#55), or `nil` when
    /// persistence is off.
    static func facetsKey(_ restorationKey: String?) -> String? {
        restorationKey.map { "facets.\($0)" }
    }

    /// The `UserDefaults` key the free-text query persists under.
    static func queryKey(_ restorationKey: String?) -> String? {
        restorationKey.map { "query.\($0)" }
    }

    /// Clears persisted live query state for one account without touching other tenants.
    static func clear(accountID: UUID, defaults: UserDefaults = .standard) {
        let suffix = ".\(accountID.uuidString)"
        let prefixes = ["query.", "filter.", "facets."]
        for key in defaults.dictionaryRepresentation().keys
            where key.hasSuffix(suffix) && prefixes.contains(where: key.hasPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    static func restoredQuery(key: String?, defaults: UserDefaults = .standard) -> String {
        guard let key else { return "" }

        return defaults.string(forKey: key) ?? ""
    }

    static func persistQuery(_ query: String, key: String?, defaults: UserDefaults = .standard) {
        guard let key else { return }

        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(query, forKey: key)
        }
    }

    /// The saved facet selection for `key` (#55), or empty when absent/unreadable.
    static func restoredFacets(
        key: String?,
        validIDs: Set<String>? = nil,
        defaults: UserDefaults = .standard
    ) -> [String: Set<String>] {
        guard let key, let data = defaults.data(forKey: key),
              let raw = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }

        let restored = raw.mapValues(Set.init).filter { !$0.value.isEmpty }
        let valid = validIDs.map { ids in restored.filter { ids.contains($0.key) } } ?? restored
        if valid != restored {
            persistFacets(valid, key: key, defaults: defaults)
        }
        return valid
    }

    /// Persists the active facet selection under `key` (#55), clearing it when nothing is
    /// selected. Empty per-facet sets are dropped so a cleared facet doesn't linger.
    static func persistFacets(_ selected: [String: Set<String>], key: String?, defaults: UserDefaults = .standard) {
        guard let key else { return }

        let nonEmpty = selected.filter { !$0.value.isEmpty }
        if nonEmpty.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(try? JSONEncoder().encode(nonEmpty.mapValues(Array.init)), forKey: key)
        }
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
