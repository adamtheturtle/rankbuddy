//
//  LoadableList.swift
//  rankbuddy-macos
//

import AppKit
import BuddyAppKit
import BuddyDesignSystem
import FastList
import HackerRankKit
import SwiftUI

/// A named way to order a list's items, shown in the list's sort menu.
struct SortOption<Item>: Identifiable {
    let id = UUID()
    let label: String
    /// A `sorted(by:)` predicate: returns true when `lhs` should come before `rhs`.
    let areInIncreasingOrder: (Item, Item) -> Bool

    init(_ label: String, by areInIncreasingOrder: @escaping (Item, Item) -> Bool) {
        self.label = label
        self.areInIncreasingOrder = areInIncreasingOrder
    }
}

/// A list that loads its items one page at a time and renders loading, empty, and error
/// states, with search, optional sorting, refresh, and load-more-on-scroll. The first page
/// is shown as soon as it arrives; further pages load as the user nears the end, so large
/// live collections never drain up front (#34).
///
/// Rows render through `FastList` (NSTableView-backed on macOS) for instant selection and
/// smooth scrolling at large item counts (#31). The list sits beside a **persistent detail
/// pane** in an `HSplitView` (#53): selecting a row (single-click, double-click, or Return)
/// shows its detail in the pane — no push/pop. The shown detail, the chosen sort order, and the
/// free-scroll position are persisted and restored per account (#19) when a `restorationKey` is
/// set.
///
/// `Item: Codable` so the first page can be cached to disk and restored instantly after a
/// relaunch (#102). Every list's concrete item already conforms; only the merged lists' wrapper
/// (`AccountScoped`, which never caches — it has no restoration key) needed conformance added.
struct LoadableList<Item: Identifiable & Hashable & Sendable & Codable, Row: View, Detail: View>: View {
    /// The first-load phase. Loaded items and the cursor live in their own state so further
    /// pages can append without disturbing this. Internal so the loading extension
    /// (`LoadableList+Loading.swift`) can drive it, per the repo's split-file rule.
    enum Phase {
        case loading
        case loaded
        case failed(String)
    }

    let title: String
    let emptyMessage: String
    /// Loads one page: the first page for `cursor == nil`, otherwise the page at `cursor`.
    let loadPage: (_ cursor: String?) async throws -> Page<Item>
    /// When set, the list loads pages with the active date range applied **server-side** instead
    /// of filtering loaded rows with `filterDate` (#86). Essential for large collections — the
    /// client-side date filter only sees loaded rows, so a date chip over 87k interviews would
    /// otherwise miss everything not yet paged in. Receives the cursor and the active named range;
    /// changing the range reloads, and the client-side date pass is skipped. `filterDate` is still
    /// set (it drives the chip and persistence) but isn't applied locally while this is set.
    var loadPageInDateRange: ((_ cursor: String?, _ range: String?) async throws -> Page<Item>)?
    /// When set, a non-empty search field is resolved **server-side** (#104) — see
    /// `LoadableList+Items`. `nil` keeps the client-side search the other lists use.
    var serverSearch: ((_ query: String, _ cursor: String?) async throws -> Page<Item>)?
    /// The text a row is matched against when filtering by the search field.
    let searchableText: (Item) -> String
    /// The ways the list can be ordered; the first is the default. Empty hides the menu.
    var sortOptions: [SortOption<Item>] = []
    /// The declarative filter facets shown in the bar above the list (#55). Empty hides the bar.
    var facets: [ListFacet<Item>] = []
    /// Pages auto-loaded per active client-side filter (#86); raise for small lists to scan fully.
    var searchPageCap = ListSearchPaging.pageCap
    /// Persists/restores the selected detail + scroll position per account (#19); `nil` disables it.
    var restorationKey: String?
    /// When set, the list offers a date-range filter chip; the closure supplies the date
    /// each item is filtered by (items with no date are hidden while a range is active).
    /// Drives the "filters" part of #19. `nil` hides the chip entirely.
    var filterDate: ((Item) -> Date?)?
    /// The filter chip's label, naming which date is filtered (e.g. "Attempted", "Created").
    var dateFilterLabel: String = "Date"
    /// Builds the native row context menu for an item (copy / open-in-browser / favourite).
    /// Returns an empty array for no menu.
    var contextMenu: (Item) -> [MenuItem] = { _ in [] }
    /// Opens an item in its own window (#49), matching PadBuddy's double-click / Return: the
    /// screen maps the row to a `DetailWindowValue` and calls `openWindow(value:)`. `nil` (the
    /// default) leaves double-click / Return driving the in-app detail pane instead — used by the
    /// People/Teams and merged lists, which have no standalone detail window.
    var openInWindow: ((Item) -> Void)?
    /// Called with the first page's items each time it loads, so callers can cache recent
    /// activity (#23). Not called for subsequent (load-more) pages.
    var onFirstPage: ([Item]) -> Void = { _ in }
    /// Extra leading toolbar content (e.g. a write action like "Invite Candidate", #12).
    /// Defaults to nothing, keeping read-only lists unchanged.
    var accessoryToolbar: () -> AnyView = { AnyView(EmptyView()) }
    /// The matching menu commands for the section's write actions (#101).
    var primaryMenuAction: AppCommandContext.Action?
    var secondaryMenuAction: AppCommandContext.Action?
    /// Bump this from the caller to force a reload (e.g. after a successful write refreshes
    /// the list). Changing the value re-runs the first-page load.
    var reloadToken: Int = 0
    /// When set, offers an "Export CSV" action over the shown (filtered, sorted) items (#39).
    var csvExport: (([Item]) -> String)?
    /// Suggested CSV file name (no extension).
    var csvFilename = "export"
    /// The favourite a row maps to, so the row can be dragged onto the sidebar's Favourites
    /// section to pin it (#89/#41). `nil` (the default) leaves rows non-draggable — the
    /// read-only People/Teams and merged lists, which have no favourites, opt out by not setting it.
    var favoriteRef: (Item) -> FavoriteRef? = { _ in nil }
    /// Public copy/drag data for a row (#123/#124). When absent, the row still participates in
    /// internal favourite dragging if `favoriteRef` is set, but Command-C is disabled.
    var rowTransfer: (Item) -> RowTransfer? = { _ in nil }
    /// The date shown in each row's trailing relative-date column (e.g. created/attempted/last
    /// active), matching PadBuddy's rows. `nil` (the default) hides the column, so lists with no
    /// meaningful per-row date are unchanged.
    var rowDate: ((Item) -> Date?)?
    @ViewBuilder let row: (Item) -> Row
    @ViewBuilder let detail: (Item) -> Detail

    /// Forwarded into each FastList row: FastList hosts rows in their own NSHostingView, which
    /// does not inherit the SwiftUI environment, so rows that read these stores would trap (#31).
    @Environment(AccountStore.self) private var accountStore
    // Internal (not private) so the row-accessory and command-registration helpers in
    // `LoadableList+Interaction.swift` can read them, per the repo's split-file rule.
    @Environment(FavoritesStore.self) var favorites
    @Environment(AppCommandContext.self) var commandContext
    @Environment(\.undoManager) var undoManager

    /// The live deep-link target (#122). Held as `@State` so this list observes it: when a deep
    /// link (a favourite, Open-by-URL, the menu bar) targets this list's `restorationKey`, the
    /// list reveals the item even though it is already on screen and won't reload on its own.
    /// Internal so the loading extension can consume the request, per the repo's split-file rule.
    @State var deepLinkRouter = DeepLinkRouter.shared

    /// The user's chosen list auto-refresh cadence in seconds (#69). `0`/below the minimum is
    /// off. Changing it restarts the refresh task. Internal (not private) so the auto-refresh
    /// extension in `LoadableList+AutoRefresh.swift` can read it, per the repo's split-file rule.
    @AppStorage(GeneralSettings.refreshSecondsKey) var autoRefreshSeconds = GeneralSettings
        .defaultRefreshSeconds

    /// Whether the persistent detail pane is hidden (#53), shared across every list and with the
    /// View ▸ Hide Detail Pane command (⌃⌘D). Internal so the toolbar extension's toggle reads it.
    @AppStorage(ListLayout.detailPaneHiddenKey) var detailPaneHidden = false
    /// Snap the pane swap instead of sliding it when Reduce Motion is on. Internal so the toolbar
    /// extension's toggle reads it.
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @State var phase: Phase = .loading
    /// `items`/`nextCursor`/`isLoadingMore`/`pagesLoaded` are internal so the auto-refresh
    /// extension (a separate file, for file_length) can reload in place (#69).
    @State var items: [Item] = []
    /// The absolute URL of the next page, or `nil` once every page is loaded.
    @State var nextCursor: String?
    /// Exact collection total from the most recent page envelope, when the endpoint provides one.
    @State var totalCount: Int?
    @State var isLoadingMore = false
    /// How many pages are currently loaded. Auto-refresh only fires on the first page, so it
    /// never yanks a user who has paged deep back to the top (#69).
    @State var pagesLoaded = 1
    /// Internal (not private) so the `visibleItems`/`selectedItems` extension in
    /// `LoadableList+Items.swift` can read the live query/filter/sort/selection state, per the
    /// repo's split-file rule.
    @State var query = ""
    /// The selected date-range filter (one of `NamedDateRange.options`), or `nil` for no
    /// date constraint.
    @State var dateRange: String?
    @State var sortSelection: SortOption<Item>.ID?
    /// The item shown in the persistent detail pane (#53), or `nil` for the placeholder.
    /// Internal so the loading/auto-refresh extensions can drive and reconcile it.
    @State var detailItem: Item?
    /// The selected rows (FastList multi-selection): drives the highlight and the
    /// "Export Selected" bulk action (#44).
    @State var selection: Set<Item.ID> = []
    /// The active facet selection (#55): facet id → chosen values. Internal so the
    /// `visibleItems` extension reads it; restored/persisted per account.
    @State var selectedFacets: [String: Set<String>] = [:]
    /// A one-shot scroll target honoured on the next layout (restored selection/scroll).
    /// Internal so the loading extension can set it during restoration.
    @State var scrollTarget: Item.ID?
    /// Guards restoration to once per load cycle, so navigating back doesn't re-push.
    @State var didRestore = false
    @State var isFilterLoading = false // search-paging spinner vs. a premature "No results" (#86)
    /// True while a fresh load runs *behind already-shown cached rows* (#102), so re-entering a
    /// section reads as "refreshing" in the subtitle rather than silently or with a full spinner.
    /// Set by the loading extension; only ever true when rows are already on screen.
    @State var isBackgroundRefreshing = false
    /// The list's saved searches, shown as recall chips in the filter bar (#25). Loaded on appear
    /// and when the account-scoped key changes; mutated as the user saves or deletes one. Internal
    /// so the `LoadableList+FilterBar` extension can drive them, per the repo's split-file rule.
    @State var savedSearches: [SavedSearch] = []
    /// Drives the "Save Search" naming alert raised by the bar's Save action (#25).
    @State var isNamingSearch = false
    @State var newSearchName = ""

    var body: some View {
        // Three-pane (#53): the list and a persistent detail pane sit side by side inside the
        // window's detail column, so selecting a row shows its detail without a push/pop.
        HSplitView {
            listColumn
                // maxHeight so each pane fills the window's full height: without it the panes
                // size to their content and the enclosing stack centres the short list (#111).
                .frame(minWidth: 300, idealWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            // The detail pane is dismissable (#53): hiding it drops to a single-column list,
            // mirroring PadBuddy. Driven by the shared toggle (⌃⌘D / the toolbar button).
            if !detailPaneHidden {
                detailColumn
                    .frame(minWidth: 320, idealWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
            }
        }
    }

    private var listColumn: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                // `.automatic`, not `.sidebar`: this list lives in the split view's detail
                // column, where no sidebar location is in scope. `.sidebar` placement can't be
                // realized here and logs a `sidebarPocket` "Invalid Configuration" fault (#77).
                .searchable(text: $query, placement: .automatic, prompt: "Search \(title)")
                // A customizable toolbar (#101): only the primary actions show by default; the rest
                // are available via "Customize Toolbar…". Built in `LoadableList+Toolbar`.
                .toolbar(id: "list") { customToolbar }
                // Re-runs when the account-scoped key changes, clearing any stale restored
                // pane before loading the new account's data (#19).
                .task(id: restorationKey) { await reload() }
                .task(id: autoRefreshSeconds) { await autoRefreshLoop() }
                // While a client-side filter (search/facet/date) is active, page in more (capped)
                // so the match isn't limited to the first page — see `LoadableList+Search` (#86).
                .task(id: clientFilterToken) { await autoLoadWhileFiltering() }
                // Server-side search (#104): reload as the query changes; no-op for client lists.
                .task(id: serverSearchToken) { await reloadForServerSearch() }
                .onChange(of: reloadToken) { Task { await reload() } }
                .onAppear {
                    restoreSort()
                    loadSavedSearches()
                    registerListCommands()
                }
                .onDisappear { commandContext.clearListActions() }
                // Re-load the recall chips when the account-scoped key changes, so each account
                // shows only its own saved searches (#25).
                .onChange(of: restorationKey) { loadSavedSearches() }
                .onChange(of: sortSelection) { persistSort() }
                .onChange(of: dateRange) {
                    ListQuery.persistRange(dateRange, key: ListQuery.filterKey(restorationKey))
                    // Server-side date filtering re-queries from page 1; client-side just
                    // re-filters the loaded rows on the next `visibleItems` recompute (#86).
                    if serverDateFiltering { Task { await reload() } }
                }
                .onChange(of: selectedFacets) {
                    ListQuery.persistFacets(selectedFacets, key: ListQuery.facetsKey(restorationKey))
                }
                // Selecting a row (single-click) drives the detail pane and persists it (#53/#19).
                .onChange(of: selection) {
                    syncDetail()
                    registerListCommands()
                }
                // Reveal a deep-linked item when this list is already on screen (#122): a
                // same-section favourite/Open-by-URL never changes `restorationKey`, so nothing
                // else re-reads the persisted selection.
                .onChange(of: deepLinkRouter.request) { Task { await consumeDeepLinkIfMatching() } }
        }
    }

    /// The persistent detail pane (#53): the selected item's detail, or a placeholder when
    /// nothing is selected. Its own `NavigationStack` so detail-level drill-down (a test's
    /// Candidates list) still pushes with a back button.
    private var detailColumn: some View {
        NavigationStack {
            if let detailItem {
                detail(detailItem)
            } else {
                CompactStateView(
                    title: "No Selection",
                    systemImage: "square.righthalf.filled",
                    message: "Select a row in \(title) to inspect its details."
                )
            }
        }
    }

    /// Where the free-scroll anchor is remembered (#19), or `nil` when persistence is off.
    /// Internal so the loading extension's restoration can read it.
    var scrollDefaultsKey: String? {
        restorationKey.map { "scroll.\($0)" }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            CompactStateView(
                title: "Loading \(title)",
                systemImage: "arrow.triangle.2.circlepath",
                message: "Fetching the latest rows for the current account.",
                isLoading: true
            )

        case .loaded where items.isEmpty:
            emptyState

        case .loaded:
            loadedList

        case let .failed(message):
            CompactStateView(
                title: "Couldn’t Load \(title)",
                systemImage: "exclamationmark.triangle",
                message: message,
                actionTitle: "Try Again",
                actionSystemImage: "arrow.clockwise"
            ) { Task { await reload() } }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if hasActiveFilters {
            CompactStateView(
                title: "No Results",
                systemImage: "line.3.horizontal.decrease.circle",
                message: "Clear filters or try a broader search.",
                actionTitle: "Clear Filters",
                actionSystemImage: "xmark.circle",
                action: clearAllFilters
            )
        } else {
            CompactStateView(
                title: emptyMessage,
                systemImage: "tray",
                message: "There is nothing to show for this account yet."
            )
        }
    }

    @ViewBuilder private var loadedList: some View {
        let visible = visibleItems
        VStack(spacing: 0) {
            // PadBuddy-style filter bar (#55/#25/#19): a saved-search recall row above the
            // facet chips, the inline date chip, and the Save / Clear actions. Each row renders
            // nothing when it has nothing to show, so plain lists are unchanged.
            savedSearchesBar
            filterBar

            if visible.isEmpty {
                filterEmptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FastList(visible, selection: $selection) { item in
                    HStack(spacing: 8) {
                        // The row's own content stays hit-transparent so a click anywhere on it
                        // falls through to the table for selection; only the trailing star (below)
                        // is interactive, matching PadBuddy's rows.
                        row(item)
                            .allowsHitTesting(false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        rowAccessory(item)
                    }
                    // Re-inject the stores the row + accessory read, because FastList's per-row
                    // NSHostingView doesn't inherit the SwiftUI environment (#31).
                    .environment(accountStore)
                    .environment(favorites)
                    // Pad and pin each row to the shared fixed height so content breathes and
                    // centres consistently, matching PadBuddy's rows (they read as squished when
                    // sized tightly to content).
                    .padding(.vertical, 5)
                    .padding(.leading, 2)
                    .padding(.trailing, 12)
                    .fixedFastListRowHeight()
                }
                .onDoubleClick { activate($0) }
                .onReturnKey { activate($0) }
                .rowContextMenu { contextMenu($0) }
                // Drag a row onto the sidebar's Favourites section to pin it (#89/#41). The same
                // drag now carries public text/URL fallbacks when the screen supplies them (#124).
                // The session hooks reveal the sidebar's drop zone only while a favourite is in flight.
                .onRowDrag { dragPasteboardItem(for: $0) }
                .onDragSession(began: FavoriteDragLifecycle.onBegan, ended: FavoriteDragLifecycle.onEnded)
                // FastList hosts each row in a recycled NSHostingView, so toggling a favourite
                // doesn't re-render the star on its own — the star only turns yellow once the
                // cell is rebuilt. Keying the list on the current favourites forces that rebuild
                // the moment the set changes, matching PadBuddy's `.reloadID` (#41).
                .reloadID(favoritesReloadID)
                .onTopRowChange { persistScrollAnchor($0) }
                // Load-more keys off the *bottom* of the viewport (FastList #1, shipped in 0.3.0),
                // so it fires on any window size, never stranding a list on its first page (#85).
                // Threshold is a generous prefetch lead so rows appear before the end, no stall (#87).
                .onReachEnd(threshold: 32) { Task { await loadMore() } }
                .scrollToRow(id: scrollTarget) { scrollTarget = nil }
                .onCopyCommand(perform: copySelectionProviders)
                // A floating pill at the bottom of the list while the next page loads, so it's
                // clear more rows are on the way when scrolling to the end (rather than the list
                // appearing to simply stop) (#85).
                .overlay(alignment: .bottom) {
                    if isLoadingMore { loadMoreIndicator }
                }
                .animation(.default, value: isLoadingMore)
                .navigationSubtitle(subtitle(visibleCount: visible.count))
                // Make the list itself greedy so it fills the column under the facet bar (#111).
                // Inside a VStack, FastList is otherwise offered only its ideal height, so a few
                // rows sized to content and the surrounding VStack centred them vertically.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Anchor the facet bar + list to the top of the column (matters for the filtered-empty
        // state, whose placeholder would otherwise float in the vertical centre) (#111).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
