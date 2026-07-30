//
//  LoadableList+Items.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit

nonisolated enum ListSortPersistence {
    static func fieldKey(restorationKey: String?) -> String? {
        restorationKey.map { "sort.v2.\($0).field" }
    }

    static func directionKey(restorationKey: String?) -> String? {
        restorationKey.map { "sort.v2.\($0).reversed" }
    }
}

/// The list's derived collections, split out of `LoadableList.swift` to keep that file within
/// the file-length budget. `extension` (internal), not `private extension`, so the view's body
/// in the other file can read them.
extension LoadableList {
    /// The items currently shown: filtered by search + date + facets, then sorted (#19, #55).
    var visibleItems: [Item] {
        // When the date range is applied server-side (#86), don't also filter locally — the
        // loaded rows are already the server's date-filtered result. Likewise when the search is
        // resolved server-side (#104): the loaded rows are already the server's matches, so don't
        // re-apply the local text filter (which could hide a match the server made on a field the
        // row's `searchableText` doesn't include).
        let base = ListQuery.filtered(
            items, query: isServerSearching ? "" : query, searchableText: searchableText,
            date: serverDateFiltering ? nil : filterDate, dateRange: dateRange, now: dateFilterNow
        )
        .filter { ListQuery.matchesFacets($0, facets: facets, selected: selectedFacets) }
        guard let option = sortOptions.first(where: { $0.id == sortSelection }) else { return base }

        // Reversing swaps the comparator's arguments rather than negating it, so equal
        // elements still compare false and `sorted(by:)` keeps a valid strict weak ordering.
        let forward = option.areInIncreasingOrder
        return base.sorted(by: sortReversed ? { forward($1, $0) } : forward)
    }

    /// The selected, currently-visible items — the bulk CSV export's input (#44).
    var selectedItems: [Item] {
        visibleItems.filter { selection.contains($0.id) }
    }

    /// Whether the active date range is resolved server-side rather than over loaded rows (#86).
    var serverDateFiltering: Bool {
        loadPageInDateRange != nil
    }

    /// The search field's text with surrounding whitespace removed.
    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a server-side search is currently in effect: a `serverSearch` loader is set and the
    /// search field is non-empty (#104).
    var isServerSearching: Bool {
        serverSearch != nil && !trimmedQuery.isEmpty
    }

    /// Whether visible rows are narrowed locally after the server result set is loaded. In that
    /// case the API total describes the wider server result, not the currently visible rows.
    var isLocalFiltering: Bool {
        (!isServerSearching && !trimmedQuery.isEmpty)
            || selectedFacets.contains { !$0.value.isEmpty }
            || (!serverDateFiltering && filterDate != nil && dateRange != nil)
    }

    /// The `.task(id:)` token that reloads a server-search list when its query changes (#104).
    /// Empty for client-side lists, so their reload task never fires.
    var serverSearchToken: String {
        serverSearch == nil ? "" : trimmedQuery
    }

    /// Loads one page, routing through the server-side search loader when a query is active
    /// (#104), then the server-side date loader when one is set (#86), else the plain page loader.
    func loadCurrentPage(_ cursor: String?) async throws -> Page<Item> {
        if let serverSearch, isServerSearching {
            return try await serverSearch(trimmedQuery, cursor)
        }
        if let loadPageInDateRange {
            return try await loadPageInDateRange(cursor, dateRange)
        }

        return try await loadPage(cursor)
    }

    /// Reloads the first page when a server-search query changes (#104), debounced so each
    /// keystroke doesn't fire a request. Clearing the field falls through `loadCurrentPage` to the
    /// normal first page. Keeps the shown rows on failure rather than blanking the list.
    func reloadForServerSearch() async {
        guard serverSearch != nil else { return }

        // Debounce: a rapid keystroke cancels this task (and this sleep) before any load.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        let generation = UUID()
        loadGeneration = generation
        detailItem = nil
        selection = []
        pagesLoaded = 1
        do {
            let page = try await loadCurrentPage(nil)
            guard generation == loadGeneration, !Task.isCancelled else { return }

            items = page.items
            nextCursor = page.next
            totalCount = page.totalCount
            phase = .loaded
            await autoLoadServerSearchResults()
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }

            if items.isEmpty { phase = .failed(message(for: error)) }
        }
    }

    /// Server-side search can return paged matches. Pull in a bounded number of extra pages so a
    /// narrow first page doesn't make the search surface look like it only supports one result.
    func autoLoadServerSearchResults() async {
        guard isServerSearching, nextCursor != nil else { return }

        isFilterLoading = true
        defer { isFilterLoading = false }
        var pagesLoadedThisSearch = 0
        while !Task.isCancelled,
              ListSearchPaging.shouldKeepLoading(
                  isFiltering: isServerSearching,
                  visibleMatches: visibleItems.count,
                  hasMorePages: nextCursor != nil,
                  pagesLoadedThisFilter: pagesLoadedThisSearch,
                  pageCap: searchPageCap
              ) {
            let countBeforeLoad = items.count
            await loadMore()
            pagesLoadedThisSearch += 1
            if items.count == countBeforeLoad { break }
        }
    }

    private var sortDefaultsKey: String? {
        ListSortPersistence.fieldKey(restorationKey: restorationKey)
    }

    private var sortReversedDefaultsKey: String? {
        ListSortPersistence.directionKey(restorationKey: restorationKey)
    }

    /// Restores direction only with a valid saved field, avoiding reversal of a fallback field.
    func restoreSort() {
        guard !sortOptions.isEmpty else { return }
        guard let sortDefaultsKey,
              let savedLabel = UserDefaults.standard.string(forKey: sortDefaultsKey),
              let saved = sortOptions.first(where: { $0.label == savedLabel })
        else {
            sortSelection = sortOptions.first?.id
            sortReversed = false
            return
        }

        sortSelection = saved.id
        sortReversed = sortReversedDefaultsKey.map(UserDefaults.standard.bool(forKey:)) ?? false
    }

    /// Persists the current sort order by its stable label (the option ids are per-launch).
    func persistSort() {
        guard let sortDefaultsKey, let sortReversedDefaultsKey,
              let option = sortOptions.first(where: { $0.id == sortSelection }) else { return }

        UserDefaults.standard.set(option.label, forKey: sortDefaultsKey)
        UserDefaults.standard.set(sortReversed, forKey: sortReversedDefaultsKey)
    }
}
