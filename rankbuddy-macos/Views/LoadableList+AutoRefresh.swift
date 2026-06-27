import SwiftUI

/// The list auto-refresh loop (#69), split out so `LoadableList.swift` stays under the
/// file-length limit. Driven by the General settings cadence, independent of the background
/// liveness sweep.
extension LoadableList {
    /// Reloads the list on the user's chosen cadence. The loop restarts when the interval
    /// changes (`.task(id:)`) and stops when off. A tick refreshes only while the list root
    /// shows, nothing is mid-load, and the user is on the first page — so it never pulls them
    /// out of a detail or back up a deep, paged list.
    func autoRefreshLoop() async {
        guard let interval = GeneralSettings.refreshInterval(raw: autoRefreshSeconds) else { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            if Task.isCancelled { break }

            if path.isEmpty, !isLoading, !isLoadingMore, pagesLoaded == 1 {
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
        onFirstPage(page.items)
    }
}
