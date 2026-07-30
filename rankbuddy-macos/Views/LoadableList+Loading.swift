//
//  LoadableList+Loading.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

extension LoadableList {
    // Resets and loads the first page. Cached rows show instantly while the fresh load refreshes
    // them in the background, so returning to a section does not flash a full-screen spinner.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func reload() async {
        didRestore = false
        loadMoreError = nil
        backgroundRefreshError = nil
        loadedCursors = []
        if filterDate != nil { dateRange = ListQuery.restoredRange(key: ListQuery.filterKey(restorationKey)) }
        if !facets.isEmpty { selectedFacets = ListQuery.restoredFacets(key: ListQuery.facetsKey(restorationKey)) }

        let isServerFilterReload = serverDateFiltering && dateRange != nil
        let isLoadedPhase = if case .loaded = phase {
            true
        } else {
            false
        }
        let preservesVisibleState = isServerFilterReload && isLoadedPhase && !items.isEmpty
        if !preservesVisibleState {
            detailItem = nil
            selection = []
        }
        pagesLoaded = 1

        if let key = cacheKey,
           let cached = await ListPageCache.cached([Item].self, for: key),
           !cached.items.isEmpty {
            items = cached.items
            nextCursor = cached.cursor
            totalCount = cached.totalCount
            phase = .loaded
            // Cached rows are shown immediately; the load below is a background refresh (#102).
            isBackgroundRefreshing = true
            await restoreIfNeeded(items)
        } else if preservesVisibleState {
            // Keep the current rows/detail in place until the server returns the filtered page, so
            // changing an interviews date chip doesn't flash through an empty intermediate state.
            nextCursor = nil
            totalCount = nil
            isBackgroundRefreshing = true
        } else {
            items = []
            nextCursor = nil
            totalCount = nil
            if isServerFilterReload {
                // Keep the loaded list shell in place while the server resolves the filter, so
                // restoring a filtered interviews list doesn't flash through the full-screen loader.
                phase = .loaded
                isFilterLoading = true
            } else {
                phase = .loading
            }
        }

        // Always clear refresh/filter hints once the fresh load settles, whichever way it goes.
        defer {
            isBackgroundRefreshing = false
            if isServerFilterReload { isFilterLoading = false }
        }

        do {
            let page = try await loadCurrentPage(nil)
            items = page.items
            onItemsLoaded(page.items)
            nextCursor = page.next
            totalCount = page.totalCount
            phase = .loaded
            backgroundRefreshError = nil
            await cacheFirstPage(page)
            if preservesVisibleState {
                reconcilePreservedSelection(in: items)
            } else {
                await restoreIfNeeded(items)
            }
        } catch {
            // Keep cached rows usable, but make their failed refresh and retry path explicit.
            if items.isEmpty {
                phase = .failed(message(for: error))
            } else {
                backgroundRefreshError = message(for: error)
            }
        }
    }

    /// The cache key for this section's first page, or `nil` when caching would be wrong: no
    /// restoration scope, or a server-side date range is narrowing the "first page" (#102).
    var cacheKey: String? {
        guard let restorationKey else { return nil }

        if serverDateFiltering, dateRange != nil { return nil }

        return restorationKey
    }

    /// Appends the next page when the user nears the end. A failed load-more keeps both the
    /// items and cursor, then waits for an explicit retry. Internal so the search auto-load
    /// extension (`LoadableList+Search`) can drive it too.
    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore, loadMoreError == nil else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await loadCurrentPage(cursor)
            if page.next == cursor || page.next.map(loadedCursors.contains) == true {
                loadMoreError = "The server repeated an earlier page. Retry to check again."
                return
            }
            if page.items.isEmpty, page.next != nil {
                loadMoreError = "The server returned an empty page before the end. Retry to check again."
                return
            }

            loadedCursors.insert(cursor)
            var seenIDs = Set(items.map(\.id))
            let newItems = page.items.filter { seenIDs.insert($0.id).inserted }
            items.append(contentsOf: newItems)
            onItemsLoaded(page.items)
            nextCursor = page.next
            totalCount = page.totalCount ?? totalCount
            pagesLoaded += 1
            loadMoreError = nil
            await restoreIfNeeded(items)
        } catch {
            loadMoreError = message(for: error)
        }
    }

    func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    func cacheFirstPage(_ page: Page<Item>) async {
        guard let key = cacheKey else { return }

        await ListPageCache.store(
            items: page.items, cursor: page.next, totalCount: page.totalCount, for: key
        )
    }

    /// Reconciles a preserved selection after a background server-filter reload. If the selected
    /// item is still present, refresh the detail with the new row instance; if not, clear once the
    /// replacement data is ready so the pane doesn't blank during the request.
    func reconcilePreservedSelection(in loadedItems: [Item]) {
        guard let selectedID = detailItem?.id ?? selection.first else { return }

        if let selectedItem = loadedItems.first(where: { $0.id == selectedID }) {
            selection = [selectedItem.id]
            detailItem = selectedItem
        } else {
            selection = []
            detailItem = nil
        }
    }

    /// Once per load: re-opens the last-viewed item's detail and scrolls to it, or — when no
    /// detail was open — scrolls to the saved free-scroll anchor. A missing item (deleted, a
    /// different account, or only on a not-yet-loaded page) simply leaves the list at the top
    /// — no loops, no blank pane (#19).
    func restoreIfNeeded(_ items: [Item]) async {
        guard !didRestore, detailItem == nil else { return }

        let storedDetail = restorationKey.flatMap { UserDefaults.standard.string(forKey: $0) }
        let storedAnchor = scrollDefaultsKey.flatMap { UserDefaults.standard.string(forKey: $0) }
        guard !ListRestoration.isPending(
            storedDetailID: storedDetail,
            storedAnchorID: storedAnchor,
            items: items,
            hasMorePages: nextCursor != nil
        ) else { return }

        didRestore = true
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
            // Stop if a load made no progress (e.g. it failed and exposed a retry).
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
