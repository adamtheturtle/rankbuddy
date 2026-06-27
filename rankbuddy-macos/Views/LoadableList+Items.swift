//
//  LoadableList+Items.swift
//  rankbuddy-macos
//

import Foundation

/// The list's derived collections, split out of `LoadableList.swift` to keep that file within
/// the file-length budget. `extension` (internal), not `private extension`, so the view's body
/// in the other file can read them.
extension LoadableList {
    /// The items currently shown: filtered by search + date + facets, then sorted (#19, #55).
    var visibleItems: [Item] {
        // When the date range is applied server-side (#86), don't also filter locally — the
        // loaded rows are already the server's date-filtered result.
        let base = ListQuery.filtered(
            items, query: query, searchableText: searchableText,
            date: serverDateFiltering ? nil : filterDate, dateRange: dateRange
        )
        .filter { ListQuery.matchesFacets($0, facets: facets, selected: selectedFacets) }
        let option = sortOptions.first { $0.id == sortSelection }
        return option.map { base.sorted(by: $0.areInIncreasingOrder) } ?? base
    }

    /// The selected, currently-visible items — the bulk CSV export's input (#44).
    var selectedItems: [Item] {
        visibleItems.filter { selection.contains($0.id) }
    }

    /// Whether the active date range is resolved server-side rather than over loaded rows (#86).
    var serverDateFiltering: Bool {
        loadPageInDateRange != nil
    }

    /// Loads one page, routing through the server-side date loader when one is set (passing the
    /// active range) so the date chip filters the whole collection, not just loaded rows (#86).
    func loadCurrentPage(_ cursor: String?) async throws -> Page<Item> {
        if let loadPageInDateRange {
            return try await loadPageInDateRange(cursor, dateRange)
        }

        return try await loadPage(cursor)
    }

    /// Where this list's chosen sort order is remembered between launches (#19). Keyed by title,
    /// so each collection keeps its own preference.
    private var sortDefaultsKey: String {
        "sort.\(title)"
    }

    /// Restores the saved sort order by label, falling back to the first option.
    func restoreSort() {
        guard !sortOptions.isEmpty else { return }

        let savedLabel = UserDefaults.standard.string(forKey: sortDefaultsKey)
        let saved = sortOptions.first { $0.label == savedLabel }
        sortSelection = (saved ?? sortOptions.first)?.id
    }

    /// Persists the current sort order by its stable label (the option ids are per-launch).
    func persistSort() {
        guard let option = sortOptions.first(where: { $0.id == sortSelection }) else { return }

        UserDefaults.standard.set(option.label, forKey: sortDefaultsKey)
    }
}
