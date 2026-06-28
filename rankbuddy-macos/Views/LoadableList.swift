//
//  LoadableList.swift
//  rankbuddy-macos
//

import BuddyAppKit
import BuddyDesignSystem
import FastList
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
/// smooth scrolling at large item counts (#31). Selection highlights a row; **double-click
/// or Return opens** its detail by pushing onto the list's own `NavigationStack`. The
/// selected detail, the chosen sort order, and the free-scroll position are persisted and
/// restored per account (#19) when a `restorationKey` is set.
struct LoadableList<Item: Identifiable & Hashable & Sendable, Row: View, Detail: View>: View {
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
    /// Called with the first page's items each time it loads, so callers can cache recent
    /// activity (#23). Not called for subsequent (load-more) pages.
    var onFirstPage: ([Item]) -> Void = { _ in }
    /// Extra leading toolbar content (e.g. a write action like "Invite Candidate", #12).
    /// Defaults to nothing, keeping read-only lists unchanged.
    var accessoryToolbar: () -> AnyView = { AnyView(EmptyView()) }
    /// Bump this from the caller to force a reload (e.g. after a successful write refreshes
    /// the list). Changing the value re-runs the first-page load.
    var reloadToken: Int = 0
    /// When set, offers an "Export CSV" action over the shown (filtered, sorted) items (#39).
    var csvExport: (([Item]) -> String)?
    /// Suggested CSV file name (no extension).
    var csvFilename = "export"
    @ViewBuilder let row: (Item) -> Row
    @ViewBuilder let detail: (Item) -> Detail

    // Forwarded into each FastList row: FastList hosts rows in their own NSHostingView, which
    // does not inherit the SwiftUI environment, so rows that read these stores would trap (#31).
    @Environment(AccountStore.self) private var accountStore
    @Environment(FavoritesStore.self) private var favorites

    /// The user's chosen list auto-refresh cadence in seconds (#69). `0`/below the minimum is
    /// off. Changing it restarts the refresh task. Internal (not private) so the auto-refresh
    /// extension in `LoadableList+AutoRefresh.swift` can read it, per the repo's split-file rule.
    @AppStorage(GeneralSettings.refreshSecondsKey) var autoRefreshSeconds = GeneralSettings
        .defaultRefreshSeconds

    @State var phase: Phase = .loading
    /// `items`/`nextCursor`/`isLoadingMore`/`pagesLoaded` are internal so the auto-refresh
    /// extension (a separate file, for file_length) can reload in place (#69).
    @State var items: [Item] = []
    /// The absolute URL of the next page, or `nil` once every page is loaded.
    @State var nextCursor: String?
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
    /// The pushed-detail navigation path. Internal so the auto-refresh extension can skip a
    /// tick while a detail is open (#69).
    @State var path: [Item] = []
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

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(title)
                .navigationDestination(for: Item.self, destination: detail)
                // `.automatic`, not `.sidebar`: this list lives in the split view's detail
                // column, where no sidebar location is in scope. `.sidebar` placement can't be
                // realized here and logs a `sidebarPocket` "Invalid Configuration" fault (#77).
                .searchable(text: $query, placement: .automatic, prompt: "Search \(title)")
                .toolbar {
                    accessoryToolbar()

                    if filterDate != nil {
                        FilterChipMenu(
                            title: dateFilterLabel,
                            icon: "calendar",
                            selected: $dateRange,
                            options: NamedDateRange.options,
                            formatter: { $0.capitalized }
                        )
                        .help("Filter \(title) by date")
                    }

                    if !sortOptions.isEmpty {
                        Menu {
                            Picker("Sort By", selection: $sortSelection) {
                                ForEach(sortOptions) { option in
                                    Text(option.label).tag(Optional(option.id))
                                }
                            }
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                        }
                        .help("Sort \(title)")
                    }

                    if let restorationKey {
                        SavedSearchMenu(
                            title: title,
                            restorationKey: restorationKey,
                            query: $query,
                            dateRange: $dateRange
                        )
                    }

                    if let csvExport {
                        Button {
                            CSVExport.save(csvExport(visibleItems), suggestedName: csvFilename)
                        } label: {
                            Label("Export CSV…", systemImage: "tablecells")
                        }
                        .help("Export \(title) as CSV")

                        if !selection.isEmpty {
                            Button {
                                CSVExport.save(csvExport(selectedItems), suggestedName: "\(csvFilename)-selected")
                            } label: {
                                Label("Export Selected (\(selection.count))…", systemImage: "tablecells.badge.ellipsis")
                            }
                            .help("Export the selected \(title) as CSV (#44)")
                        }
                    }

                    Button {
                        Task { await reload() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(isLoading)
                }
                // Re-runs when the account-scoped key changes, clearing any stale restored
                // pane before loading the new account's data (#19).
                .task(id: restorationKey) { await reload() }
                .task(id: autoRefreshSeconds) { await autoRefreshLoop() }
                // While a client-side filter (search/facet/date) is active, page in more (capped)
                // so the match isn't limited to the first page — see `LoadableList+Search` (#86).
                .task(id: clientFilterToken) { await autoLoadWhileFiltering() }
                .onChange(of: reloadToken) { Task { await reload() } }
                .onAppear { restoreSort() }
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
                .onChange(of: path) { persistSelection() }
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
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded where items.isEmpty:
            ContentUnavailableView(emptyMessage, systemImage: "tray")

        case .loaded:
            loadedList

        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn’t load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await reload() } }
            }
        }
    }

    @ViewBuilder private var loadedList: some View {
        let visible = visibleItems
        VStack(spacing: 0) {
            // Renders nothing when no facets are declared, so unfaceted lists are unchanged (#55).
            FacetBar(facets: facets, items: items, selected: $selectedFacets)

            if visible.isEmpty {
                filterEmptyState
            } else {
                FastList(visible, selection: $selection) { item in
                    // Re-inject the stores the rows read, because FastList's per-row NSHostingView
                    // doesn't inherit the SwiftUI environment. Non-interactive so a click falls
                    // through to the table for selection (the favourite star is a passive indicator).
                    row(item)
                        .environment(accountStore)
                        .environment(favorites)
                        .allowsHitTesting(false)
                }
                .onDoubleClick { open($0) }
                .onReturnKey { open($0) }
                .rowContextMenu { contextMenu($0) }
                .onTopRowChange { persistScrollAnchor($0) }
                // Load-more keys off the *bottom* of the viewport (FastList #1, shipped in 0.3.0),
                // so it fires on any window size, never stranding a list on its first page (#85).
                // Threshold is a generous prefetch lead so rows appear before the end, no stall (#87).
                .onReachEnd(threshold: 32) { Task { await loadMore() } }
                .scrollToRow(id: scrollTarget) { scrollTarget = nil }
                .navigationSubtitle(subtitle(visibleCount: visible.count))
            }
        }
    }

    /// A loaded-count summary, with a `+` when more pages remain to be paged in.
    private func subtitle(visibleCount: Int) -> String {
        let suffix = nextCursor != nil ? "+" : ""
        return "\(visibleCount)\(suffix) \(visibleCount == 1 ? "item" : "items")"
    }

    var isLoading: Bool {
        if case .loading = phase { true } else { false }
    }

    /// Pushes an item's detail (or no-ops if it's already on top).
    private func open(_ item: Item) {
        guard path.last != item else { return }

        path = [item]
    }

    /// Persists the current top row as the free-scroll anchor for restoration (#19). Load-more
    /// is driven separately by `onReachEnd` (the bottom of the viewport), not from here.
    private func persistScrollAnchor(_ topID: Item.ID?) {
        guard let scrollDefaultsKey, let topID else { return }

        UserDefaults.standard.set(String(describing: topID), forKey: scrollDefaultsKey)
    }

    /// Remembers the currently selected item (the top of the path), or clears it on pop.
    private func persistSelection() {
        guard let restorationKey else { return }

        if let selected = path.last {
            UserDefaults.standard.set(String(describing: selected.id), forKey: restorationKey)
        } else {
            UserDefaults.standard.removeObject(forKey: restorationKey)
        }
    }
}
