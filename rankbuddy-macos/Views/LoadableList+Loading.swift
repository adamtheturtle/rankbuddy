//
//  LoadableList+Loading.swift
//  rankbuddy-macos
//

import HackerRankKit
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
            totalCount = nil
            phase = .loaded
            // Cached rows are shown immediately; the load below is a background refresh (#102).
            isBackgroundRefreshing = true
            onFirstPage(cached.items)
            await restoreIfNeeded(items)
        } else {
            phase = .loading
            items = []
            nextCursor = nil
            totalCount = nil
        }

        // Always clear the refresh hint once the fresh load settles, whichever way it goes.
        defer { isBackgroundRefreshing = false }

        do {
            let page = try await loadCurrentPage(nil)
            items = page.items
            nextCursor = page.next
            totalCount = page.totalCount
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
            totalCount = page.totalCount ?? totalCount
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

    /// Handles a live deep-link request (#122) when it targets this list. Consumes the request so
    /// it fires once, then reveals the item — selecting its row and scrolling to it — paging in
    /// further rows (capped) if it isn't on a loaded page yet.
    func consumeDeepLinkIfMatching() async {
        guard let request = deepLinkRouter.request, request.key == restorationKey else { return }

        deepLinkRouter.request = nil
        await revealItem(id: request.itemID)
    }

    /// Selects and scrolls to the item with the given persisted id. If it isn't among the loaded
    /// rows, pages in more (bounded by `searchPageCap`, mirroring the filter auto-load) until it
    /// appears or the list is exhausted; a still-missing item leaves the list untouched.
    private func revealItem(id: String) async {
        if select(id: id) { return }

        var pagesLoadedThisReveal = 0
        while nextCursor != nil, pagesLoadedThisReveal < searchPageCap {
            let countBeforeLoad = items.count
            await loadMore()
            pagesLoadedThisReveal += 1
            if select(id: id) { return }
            // Stop if a load made no progress (e.g. it failed and cleared the cursor).
            if items.count == countBeforeLoad { return }
        }
    }

    /// Selects the loaded item matching the persisted id and drives the detail pane, returning
    /// whether it was found among the current rows.
    @discardableResult
    private func select(id: String) -> Bool {
        guard let item = items.first(where: { String(describing: $0.id) == id }) else { return false }

        selection = [item.id]
        detailItem = item
        scrollTarget = item.id
        return true
    }
}
