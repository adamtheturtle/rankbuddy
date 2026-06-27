//
//  LoadableList+Search.swift
//  rankbuddy-macos
//

import SwiftUI

/// The auto-load policy for client-side filtering (#86), factored out of the (generic) list so
/// it's unit-testable.
///
/// Search, facets, and (for most lists) the date chip filter loaded rows client-side, and the
/// HackerRank API has no free-text *name* search param, so on a large collection (3,615 users,
/// 87k interviews) a filter would only ever match the first page. While a filter is active this
/// pages in more rows so the match runs over far more of the collection — bounded, so a vague
/// filter can't drain an 87k list: it stops once there are enough matches to fill the view, the
/// list is exhausted, or a page cap is hit (after which the list's `+` count still signals there
/// are more unmatched rows to scroll).
enum ListSearchPaging {
    /// Stop auto-loading once this many matches are visible — enough to fill the view; the user
    /// can scroll for more, which pages in further rows as usual.
    static let matchTarget = 30
    /// The default cap on pages auto-loaded for a single active filter, so a low-signal filter
    /// over a huge collection stays bounded (≈ this × page size rows scanned). A list can raise it
    /// (via `LoadableList.searchPageCap`) when the collection is small enough to scan fully.
    static let pageCap = 20

    /// Whether to keep paging for the active filter: something is filtering, more pages are
    /// available, fewer than `matchTarget` matches so far, and under `pageCap`.
    static func shouldKeepLoading(
        isFiltering: Bool,
        visibleMatches: Int,
        hasMorePages: Bool,
        pagesLoadedThisFilter: Int,
        pageCap: Int = pageCap
    ) -> Bool {
        isFiltering
            && hasMorePages
            && visibleMatches < matchTarget
            && pagesLoadedThisFilter < pageCap
    }
}

extension LoadableList {
    /// A change token over every client-side filter, so `.task(id:)` restarts the auto-load when
    /// the search text, facet selection, or (client-side) date range changes.
    var clientFilterToken: String {
        let facetSignature = selectedFacets
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value.sorted().joined(separator: ","))" }
            .joined(separator: ";")
        // The interviews date range is applied server-side, so it isn't part of the client filter.
        let clientDate = serverDateFiltering ? "" : (dateRange ?? "")
        return "\(query)|\(facetSignature)|\(clientDate)"
    }

    /// Whether any client-side narrowing filter is currently active.
    var isClientFiltering: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedFacets.contains { !$0.value.isEmpty }
            || (!serverDateFiltering && filterDate != nil && dateRange != nil)
    }

    /// The empty state shown when a filter matches nothing in the loaded rows: a "Searching…"
    /// spinner while more pages are still being paged in (#86), so a slow scan over a large
    /// collection (e.g. finding one person among thousands) doesn't read as a premature "No
    /// results"; the real "No results" shows only once the scan has settled.
    @ViewBuilder var filterEmptyState: some View {
        if isFilterLoading {
            ProgressView("Searching…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView.search(text: query).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Pages in more rows while a client-side filter is active so the match isn't limited to the
    /// first page (#86). Driven by `.task(id: clientFilterToken)`, so SwiftUI cancels and restarts
    /// it as the filter changes — which also debounces typing via the initial sleep.
    func autoLoadWhileFiltering() async {
        guard isClientFiltering, nextCursor != nil else { return }

        // Debounce: a rapid keystroke/toggle cancels this task (and this sleep) before any load.
        try? await Task.sleep(for: .milliseconds(350))

        isFilterLoading = true
        defer { isFilterLoading = false }
        var pagesLoadedThisFilter = 0
        while !Task.isCancelled,
              ListSearchPaging.shouldKeepLoading(
                  isFiltering: isClientFiltering,
                  visibleMatches: visibleItems.count,
                  hasMorePages: nextCursor != nil,
                  pagesLoadedThisFilter: pagesLoadedThisFilter,
                  pageCap: searchPageCap
              ) {
            let countBeforeLoad = items.count
            await loadMore()
            pagesLoadedThisFilter += 1
            // Stop if a load made no progress (e.g. it failed and cleared the cursor), so we
            // never spin.
            if items.count == countBeforeLoad { break }
        }
    }
}
