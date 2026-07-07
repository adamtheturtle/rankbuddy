//
//  LoadableList+AutoRefresh.swift
//  rankbuddy-macos
//

import AsyncAlgorithms
import SwiftUI

/// The list auto-refresh loop (#69), split out so `LoadableList.swift` stays under the
/// file-length limit. Driven by the General settings cadence, independent of the background
/// liveness sweep.
extension LoadableList {
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
        guard let page = try? await loadPage(nil) else { return }

        items = page.items
        nextCursor = page.next
        totalCount = page.totalCount
        onFirstPage(page.items)
        // Drop the pane's item if the refresh removed it (e.g. deleted elsewhere), so the
        // detail never shows a row that's no longer in the list.
        if let detailItem, !items.contains(where: { $0.id == detailItem.id }) {
            self.detailItem = nil
        }
    }
}
