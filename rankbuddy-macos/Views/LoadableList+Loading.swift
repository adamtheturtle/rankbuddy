//
//  LoadableList+Loading.swift
//  rankbuddy-macos
//

import SwiftUI

extension LoadableList {
    /// Resets and loads the first page (initial load, refresh, or account switch).
    ///
    /// When a cached first page exists for this section it is shown instantly and the fresh load
    /// refreshes it in the background, so re-entering a section never flashes a full-screen
    /// spinner (#102). Only the unfiltered first page is cached, so a restored server-side date
    /// range still loads fresh.
    func reload() async {
        didRestore = false
        if filterDate != nil { dateRange = ListQuery.restoredRange(key: ListQuery.filterKey(restorationKey)) }
        if !facets.isEmpty { selectedFacets = ListQuery.restoredFacets(key: ListQuery.facetsKey(restorationKey)) }
        detailItem = nil
        selection = []
        pagesLoaded = 1

        if let key = cacheKey, let cached = ListPageCache.cached([Item].self, for: key), !cached.items.isEmpty {
            items = cached.items
            nextCursor = cached.cursor
            phase = .loaded
            onFirstPage(cached.items)
            await restoreIfNeeded(items)
        } else {
            phase = .loading
            items = []
            nextCursor = nil
        }

        do {
            let page = try await loadCurrentPage(nil)
            items = page.items
            nextCursor = page.next
            phase = .loaded
            onFirstPage(page.items)
            if let key = cacheKey { ListPageCache.store(items: page.items, cursor: page.next, for: key) }
            await restoreIfNeeded(items)
        } catch {
            // Keep showing cached rows on a refresh failure; only surface the error when there
            // was nothing to show.
            if items.isEmpty { phase = .failed(message(for: error)) }
        }
    }

    /// The cache key for this section's first page, or `nil` when caching would be wrong: no
    /// restoration scope, or a server-side date range is narrowing the "first page" (#102).
    var cacheKey: String? {
        guard let restorationKey else { return nil }

        if serverDateFiltering, dateRange != nil { return nil }

        return restorationKey
    }

    /// Appends the next page when the user nears the end. A failed load-more keeps the
    /// items already shown and stops paging rather than discarding the list. Internal so the
    /// search auto-load extension (`LoadableList+Search`) can drive it too.
    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await loadCurrentPage(cursor)
            items.append(contentsOf: page.items)
            nextCursor = page.next
            pagesLoaded += 1
        } catch {
            nextCursor = nil
        }
    }

    func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// Once per load: re-opens the last-viewed item's detail and scrolls to it, or — when no
    /// detail was open — scrolls to the saved free-scroll anchor. A missing item (deleted, a
    /// different account, or only on a not-yet-loaded page) simply leaves the list at the top
    /// — no loops, no blank pane (#19).
    func restoreIfNeeded(_ items: [Item]) async {
        guard !didRestore, detailItem == nil else { return }

        didRestore = true

        let storedDetail = restorationKey.flatMap { UserDefaults.standard.string(forKey: $0) }
        let storedAnchor = scrollDefaultsKey.flatMap { UserDefaults.standard.string(forKey: $0) }

        switch ListRestoration.action(storedDetailID: storedDetail, storedAnchorID: storedAnchor, items: items) {
        case let .restoreDetail(item):
            // Reselect the row and show its detail in the persistent pane (#53/#19).
            selection = [item.id]
            detailItem = item
            scrollTarget = item.id

        case let .restoreScroll(item):
            scrollTarget = item.id

        case .startAtTop:
            break
        }
    }
}
