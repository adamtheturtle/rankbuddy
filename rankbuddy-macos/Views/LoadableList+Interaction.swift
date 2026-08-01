//
//  LoadableList+Interaction.swift
//  rankbuddy-macos
//

import AppKit
import SwiftUI

/// A structured, order-independent FastList reload identity. Keeping IDs as array elements avoids
/// delimiter collisions such as `["a", "b|c"]` and `["a|b", "c"]`.
nonisolated struct FavoritesReloadIdentity: Hashable {
    let ids: [String]

    init(ids: [String]) {
        self.ids = ids.sorted()
    }
}

/// Row accessories, copy/drag providers, the write-action command registration, and the
/// selection/scroll persistence that back `LoadableList`. Split out of `LoadableList.swift`
/// to keep that file within the repo's length limits, per the repo's split-file rule.
extension LoadableList {
    func partialLoadFailure(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry") {
                Task { await reload() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.12))
        .accessibilityElement(children: .combine)
    }

    /// The interactive trailing column shared by every row: a clickable favourite star (for
    /// lists that map rows to a `favoriteRef`) and an adaptive relative-date column (for lists
    /// that set `rowDate`), matching PadBuddy. Rendered outside the row's hit-transparent content
    /// so the star toggles on click while the rest of the row still selects.
    func rowAccessory(_ item: Item) -> some View {
        HStack(spacing: 8) {
            if let ref = favoriteRef(item) {
                FavoriteStarButton(
                    isFavorite: favorites.isFavorite(
                        collection: ref.collection,
                        accountID: ref.accountID,
                        itemID: ref.itemID
                    ),
                    title: ref.title,
                    toggle: { favorites.toggle(ref, undoManager: undoManager) }
                )
            }
            if let rowDate {
                RowDateLabel(date: rowDate(item))
                    .allowsHitTesting(false)
            }
        }
    }

    /// A change token over the current favourites, used as the FastList `reloadID` so the star
    /// column rebuilds (and turns yellow) the instant an item is pinned or unpinned. Sorted so the
    /// token is order-independent — only membership changes trigger a reload, not reordering.
    var favoritesReloadID: FavoritesReloadIdentity {
        FavoritesReloadIdentity(ids: favorites.favorites.map(\.id))
    }

    /// A floating "Loading more…" pill shown over the bottom of the list while the next page
    /// is being fetched (#85), so reaching the end reads as "more coming" rather than "the end".
    var loadMoreIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading more…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
        .padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    func loadMoreFailure(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Text(message)
                .lineLimit(2)
            Button("Retry") {
                loadMoreError = nil
                Task { await loadMore() }
            }
        }
        .font(.callout)
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    func backgroundRefreshFailure(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Text("Couldn’t refresh: \(message)")
                .lineLimit(2)
            Spacer()
            Button("Retry") {
                Task { await reload() }
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.12))
    }

    /// A loaded-count summary. Prefer the API's exact total when available; fall back to the
    /// loaded visible count while more pages remain.
    func subtitle(visibleCount: Int) -> String {
        let exactTotal = isLocalFiltering ? nil : totalCount
        let displayedCount = exactTotal ?? visibleCount
        let count = "\(displayedCount) \(displayedCount == 1 ? "item" : "items")"
        return isBackgroundRefreshing ? "\(count) · Refreshing…" : count
    }

    var isLoading: Bool {
        if case .loading = phase { true } else { false }
    }

    /// Double-click / Return on a row: opens the item in its own window when the screen supports
    /// one (#49), matching PadBuddy — single-click already drives the persistent pane, so the
    /// second click escalates to a standalone window. Lists without a `DetailWindowValue` mapping
    /// (People/Teams, merged) fall back to showing the item in the pane.
    func activate(_ item: Item) {
        if let openInWindow {
            selection = [item.id]
            onOpen(item)
            openInWindow(item)
        } else {
            open(item)
        }
    }

    /// Opens an item's detail in the persistent pane. Single-click selection drives the same path
    /// via `syncDetail`; used by `activate` as the fallback for lists with no standalone window.
    func open(_ item: Item) {
        selection = [item.id]
        detailItem = item
        onOpen(item)
    }

    /// Providers for the system Copy command. Multi-selection copies every selected visible row;
    /// an empty selection falls back to the detail row so Command-C after opening a detail still
    /// has useful behavior.
    func copySelectionProviders() -> [NSItemProvider] {
        RowTransfer.itemProviders(for: activeTransfers)
    }

    private var activeTransfers: [RowTransfer] {
        let rows = selection.isEmpty ? detailItem.map { [$0] } ?? [] : selectedItems
        return rows.compactMap(rowTransfer)
    }

    func dragPasteboardItem(for item: Item) -> NSPasteboardItem? {
        // Dragging one row of a multi-selection carries every selected row's public data, so a
        // drop onto TextEdit, Numbers, or a browser receives them all (#124), matching PadBuddy.
        // The app-private favourite payload is single-row only (one drop pins one item), so a
        // multi-row drag intentionally omits it.
        if selection.count > 1, selection.contains(item.id),
           let multi = RowTransfer.pasteboardItem(for: selectedItems.compactMap(rowTransfer)) {
            return multi
        }

        let ref = favoriteRef(item)
        if let transfer = rowTransfer(item) {
            return transfer.pasteboardItem(favoriteRef: ref)
        }
        return ref.flatMap(FavoritePasteboard.item(for:))
    }

    func registerListCommands() {
        // Reload drives ⌘R from the Go menu, so the toolbar's Refresh button can be hidden from
        // the default toolbar (available via Customize) exactly like PadBuddy's Reload (#101).
        let refresh = AppCommandContext.Action(
            title: "Reload \(title)",
            isEnabled: { !isLoading },
            perform: { Task { await reload() } }
        )
        let exportCSV = csvExport.map { csvExport in
            let exportTitle = csvExportIsPartial ? "Export Loaded \(title) Rows CSV…" : "Export \(title) CSV…"
            return AppCommandContext.Action(title: exportTitle) {
                let snapshot = visibleItems
                CSVExport.save({ csvExport(snapshot) }, suggestedName: csvExportSuggestedName)
            }
        }
        let exportSelectedCSV = csvExport.map { csvExport in
            let selectedCount = selectedItems.count
            return AppCommandContext.Action(
                title: selectedCount == 0 ? "Export Selected CSV…" : "Export Selected CSV (\(selectedCount))…",
                isEnabled: { !selectedItems.isEmpty },
                perform: {
                    let snapshot = selectedItems
                    guard !snapshot.isEmpty else { return }

                    CSVExport.save({ csvExport(snapshot) }, suggestedName: "\(csvFilename)-selected")
                }
            )
        }
        commandContext.registerListActions(
            owner: commandOwner,
            actions: AppCommandContext.ListActions(
                primaryNew: primaryMenuAction,
                secondaryNew: secondaryMenuAction,
                exportCSV: exportCSV,
                exportSelectedCSV: exportSelectedCSV,
                refresh: refresh
            )
        )
    }

    /// Reflects the row selection into the detail pane (#53): when exactly one row is selected,
    /// that item's detail shows; a multi-select (bulk export, #44) or empty selection keeps the
    /// last detail rather than flickering to the placeholder. Persists the choice for restore.
    func syncDetail() {
        if selection.count == 1, let id = selection.first, let item = items.first(where: { $0.id == id }) {
            detailItem = item
            onOpen(item)
        }
        persistSelection()
    }

    /// Filtering must not leave commands or a detail pane targeting a row hidden from the result.
    func reconcileSelectionWithVisibleItems() {
        let visibleIDs = Set(visibleItems.map(\.id))
        selection.formIntersection(visibleIDs)
        guard let detailItem, !visibleIDs.contains(detailItem.id) else { return }

        self.detailItem = nil
        persistSelection()
    }

    /// Persists the current top row as the free-scroll anchor for restoration (#19). Load-more
    /// is driven separately by `onReachEnd` (the bottom of the viewport), not from here.
    func persistScrollAnchor(_ topID: Item.ID?) {
        guard let scrollDefaultsKey else { return }

        if let topID {
            UserDefaults.standard.set(String(describing: topID), forKey: scrollDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: scrollDefaultsKey)
        }
    }

    /// Remembers the item shown in the detail pane so it is reselected on relaunch (#19).
    private func persistSelection() {
        guard let restorationKey else { return }

        if let selected = detailItem {
            UserDefaults.standard.set(String(describing: selected.id), forKey: restorationKey)
        } else {
            UserDefaults.standard.removeObject(forKey: restorationKey)
        }
    }
}
