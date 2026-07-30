//
//  LoadableList+AutoRefresh.swift
//  rankbuddy-macos
//

import AsyncAlgorithms
import HackerRankKit
import SwiftUI

/// The list auto-refresh loop (#69), split out so `LoadableList.swift` stays under the
/// file-length limit. Driven by the General settings cadence, independent of the background
/// liveness sweep.
extension LoadableList {
    /// Invalidates client-side rolling ranges as time advances and refreshes server-side ranges
    /// when their calendar-day bounds cross midnight.
    func rollingDateFilterLoop() async {
        guard filterDate != nil, dateRange != nil else { return }

        var day = Calendar.current.startOfDay(for: dateFilterNow)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }

            let now = Date()
            dateFilterNow = now
            let currentDay = Calendar.current.startOfDay(for: now)
            if serverDateFiltering, currentDay != day {
                day = currentDay
                await reload()
            }
        }
    }

    /// Reloads the list on the user's chosen cadence. The loop restarts when the interval
    /// changes (`.task(id:)`) and stops when off. A tick refreshes only while nothing is
    /// mid-load and the user is on the first page — so it never interrupts a load or pulls them
    /// back up a deep, paged list. The persistent detail pane (#53) is unaffected: it holds its
    /// own item, so refreshing the list beside it never disturbs the open detail.
    func autoRefreshLoop() async {
        guard let interval = GeneralSettings.refreshInterval(raw: autoRefreshSeconds) else { return }

        for await _ in AsyncTimerSequence.repeating(every: interval) {
            if !isLoading, !isLoadingMore, pagesLoaded == 1 {
                await quietRefresh()
            }
        }
    }

    /// Re-fetches the first page in place, without the loading spinner. A transient failure
    /// keeps the items already shown; the next tick retries.
    func quietRefresh() async {
        let generation = loadGeneration
        let page: Page<Item>
        do {
            page = try await loadPage(nil)
        } catch {
            guard generation == loadGeneration else { return }

            backgroundRefreshError = message(for: error)
            return
        }
        guard generation == loadGeneration else { return }

        items = page.items
        backgroundRefreshError = nil
        onItemsLoaded(page.items)
        nextCursor = page.next
        totalCount = page.totalCount
        await cacheFirstPage(page, for: cacheKey)
        // Refresh the detail from the replacement row, or atomically clear both detail and
        // selection if the item disappeared elsewhere.
        reconcilePreservedSelection(in: items)
    }
}
