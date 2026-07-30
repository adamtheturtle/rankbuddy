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
    }

    /// Providers for the system Copy command. Multi-selection copies every selected visible row;
    /// an empty selection falls back to the detail row so Command-C after opening a detail still
    /// has useful behavior.
    func copySelectionProviders() -> [NSItemProvider] {
        RowTransfer.itemProviders(for: activeTransfers)
    }

    private var activeTransfers: [RowTransfer] {
        let rows = selectedItems.isEmpty ? detailItem.map { [$0] } ?? [] : selectedItems
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
        commandContext.primaryNew = primaryMenuAction
        commandContext.secondaryNew = secondaryMenuAction
        // Reload drives ⌘R from the Go menu, so the toolbar's Refresh button can be hidden from
        // the default toolbar (available via Customize) exactly like PadBuddy's Reload (#101).
        commandContext.refresh = AppCommandContext.Action(
            title: "Reload \(title)",
            isEnabled: { !isLoading },
            perform: { Task { await reload() } }
        )
        guard let csvExport else {
            commandContext.exportCSV = nil
            commandContext.exportSelectedCSV = nil
            return
        }

        let exportTitle = csvExportIsPartial ? "Export Loaded \(title) Rows CSV…" : "Export \(title) CSV…"
        commandContext.exportCSV = AppCommandContext.Action(title: exportTitle) {
            CSVExport.save(csvExport(visibleItems), suggestedName: csvExportSuggestedName)
        }
        commandContext.exportSelectedCSV = AppCommandContext.Action(
            title: selection.isEmpty ? "Export Selected CSV…" : "Export Selected CSV (\(selection.count))…",
            isEnabled: { !selection.isEmpty },
            perform: { CSVExport.save(csvExport(selectedItems), suggestedName: "\(csvFilename)-selected") }
        )
    }

    /// Reflects the row selection into the detail pane (#53): when exactly one row is selected,
    /// that item's detail shows; a multi-select (bulk export, #44) or empty selection keeps the
    /// last detail rather than flickering to the placeholder. Persists the choice for restore.
    func syncDetail() {
        if selection.count == 1, let id = selection.first, let item = items.first(where: { $0.id == id }) {
            detailItem = item
        }
        persistSelection()
    }

    /// Persists the current top row as the free-scroll anchor for restoration (#19). Load-more
    /// is driven separately by `onReachEnd` (the bottom of the viewport), not from here.
    func persistScrollAnchor(_ topID: Item.ID?) {
        guard let scrollDefaultsKey, let topID else { return }

        UserDefaults.standard.set(String(describing: topID), forKey: scrollDefaultsKey)
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
