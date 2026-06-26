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
    /// pages can append without disturbing this.
    private enum Phase {
        case loading
        case loaded
        case failed(String)
    }

    let title: String
    let emptyMessage: String
    /// Loads one page: the first page for `cursor == nil`, otherwise the page at `cursor`.
    let loadPage: (_ cursor: String?) async throws -> Page<Item>
    /// The text a row is matched against when filtering by the search field.
    let searchableText: (Item) -> String
    /// The ways the list can be ordered; the first is the default. Empty hides the menu.
    var sortOptions: [SortOption<Item>] = []
    /// When set, the list persists/restores the selected detail and scroll position across
    /// launches under this key (#19). Callers scope the key by account and collection. `nil`
    /// (e.g. the nested per-test candidates list) disables persistence but not navigation.
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
    @ViewBuilder let row: (Item) -> Row
    @ViewBuilder let detail: (Item) -> Detail

    // Forwarded into each FastList row: FastList hosts rows in their own NSHostingView, which
    // does not inherit the SwiftUI environment, so rows that read these stores would trap (#31).
    @Environment(AccountStore.self) private var accountStore
    @Environment(FavoritesStore.self) private var favorites

    @State private var phase: Phase = .loading
    @State private var items: [Item] = []
    /// The absolute URL of the next page, or `nil` once every page is loaded.
    @State private var nextCursor: String?
    @State private var isLoadingMore = false
    @State private var query = ""
    /// The selected date-range filter (one of `NamedDateRange.options`), or `nil` for no
    /// date constraint.
    @State private var dateRange: String?
    @State private var sortSelection: SortOption<Item>.ID?
    /// The pushed-detail navigation path.
    @State private var path: [Item] = []
    /// The highlighted row (FastList selection); drives nothing but the highlight.
    @State private var selection: Item.ID?
    /// A one-shot scroll target honoured on the next layout (restored selection/scroll).
    @State private var scrollTarget: Item.ID?
    /// Guards restoration to once per load cycle, so navigating back doesn't re-push.
    @State private var didRestore = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(title)
                .navigationDestination(for: Item.self, destination: detail)
                .searchable(text: $query, placement: .sidebar, prompt: "Search \(title)")
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
                .onChange(of: reloadToken) { Task { await reload() } }
                .onAppear { restoreSort() }
                .onChange(of: sortSelection) { persistSort() }
                .onChange(of: dateRange) { persistFilter() }
                .onChange(of: path) { persistSelection() }
        }
    }

    /// Where this list's chosen sort order is remembered between launches (#19). Keyed by
    /// title, so each collection keeps its own preference.
    private var sortDefaultsKey: String {
        "sort.\(title)"
    }

    /// Where the free-scroll anchor is remembered (#19), or `nil` when persistence is off.
    private var scrollDefaultsKey: String? {
        restorationKey.map { "scroll.\($0)" }
    }

    /// Restores the saved sort order by label, falling back to the first option.
    private func restoreSort() {
        guard !sortOptions.isEmpty else { return }

        let savedLabel = UserDefaults.standard.string(forKey: sortDefaultsKey)
        let saved = sortOptions.first { $0.label == savedLabel }
        sortSelection = (saved ?? sortOptions.first)?.id
    }

    /// Persists the current sort order by its stable label (the option ids are per-launch).
    private func persistSort() {
        guard let option = sortOptions.first(where: { $0.id == sortSelection }) else { return }

        UserDefaults.standard.set(option.label, forKey: sortDefaultsKey)
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
        let visible = sort(filter(items))
        if visible.isEmpty {
            ContentUnavailableView.search(text: query)
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
            .onTopRowChange { topRowChanged(to: $0, in: visible) }
            .scrollToRow(id: scrollTarget) { scrollTarget = nil }
            .navigationSubtitle(subtitle(visibleCount: visible.count))
        }
    }

    /// A loaded-count summary, with a `+` when more pages remain to be paged in.
    private func subtitle(visibleCount: Int) -> String {
        let suffix = nextCursor != nil ? "+" : ""
        return "\(visibleCount)\(suffix) \(visibleCount == 1 ? "item" : "items")"
    }

    private func filter(_ items: [Item]) -> [Item] {
        var result = items
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result = result.filter { searchableText($0).localizedCaseInsensitiveContains(trimmed) }
        }

        if let filterDate {
            result = DateRangeFilter.apply(result, range: dateRange, date: filterDate)
        }

        return result
    }

    private func sort(_ items: [Item]) -> [Item] {
        guard let option = sortOptions.first(where: { $0.id == sortSelection }) else { return items }

        return items.sorted(by: option.areInIncreasingOrder)
    }

    private var isLoading: Bool {
        if case .loading = phase { true } else { false }
    }

    /// Pushes an item's detail (or no-ops if it's already on top).
    private func open(_ item: Item) {
        guard path.last != item else { return }

        path = [item]
    }

    /// When a settled scroll leaves the top row near the end, page in the next chunk (#34);
    /// also persists the anchor for scroll restoration (#19).
    private func topRowChanged(to topID: Item.ID?, in visible: [Item]) {
        if let scrollDefaultsKey, let topID {
            UserDefaults.standard.set(String(describing: topID), forKey: scrollDefaultsKey)
        }

        guard nextCursor != nil, !isLoadingMore, let topID,
              let index = visible.firstIndex(where: { $0.id == topID })
        else { return }

        if index >= visible.count - 12 {
            Task { await loadMore() }
        }
    }

    /// Resets and loads the first page (initial load, refresh, or account switch).
    private func reload() async {
        didRestore = false
        restoreFilter()
        path = []
        selection = nil
        phase = .loading
        items = []
        nextCursor = nil
        do {
            let page = try await loadPage(nil)
            items = page.items
            nextCursor = page.next
            phase = .loaded
            onFirstPage(page.items)
            restoreIfNeeded(items)
        } catch {
            phase = .failed(message(for: error))
        }
    }

    /// Appends the next page when the user nears the end. A failed load-more keeps the
    /// items already shown and stops paging rather than discarding the list.
    private func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await loadPage(cursor)
            items.append(contentsOf: page.items)
            nextCursor = page.next
        } catch {
            nextCursor = nil
        }
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// Once per load: re-opens the last-viewed item's detail and scrolls to it, or — when no
    /// detail was open — scrolls to the saved free-scroll anchor. A missing item (deleted, a
    /// different account, or only on a not-yet-loaded page) simply leaves the list at the top
    /// — no loops, no blank pane (#19).
    private func restoreIfNeeded(_ items: [Item]) {
        guard !didRestore, path.isEmpty else { return }

        didRestore = true

        if let restorationKey,
           let stored = UserDefaults.standard.string(forKey: restorationKey),
           let item = items.first(where: { String(describing: $0.id) == stored }) {
            selection = item.id
            scrollTarget = item.id
            path = [item]
            return
        }

        if let scrollDefaultsKey,
           let anchor = UserDefaults.standard.string(forKey: scrollDefaultsKey),
           let item = items.first(where: { String(describing: $0.id) == anchor }) {
            scrollTarget = item.id
        }
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

// MARK: - Date-filter persistence (#19)

private extension LoadableList {
    /// Where the chosen date filter is remembered (#19), or `nil` when persistence is off.
    /// Scoped by `restorationKey`, so each account/collection keeps its own filter.
    var filterDefaultsKey: String? {
        restorationKey.map { "filter.\($0)" }
    }

    /// Restores the saved date filter for the current key, ignoring any stale/unknown value.
    func restoreFilter() {
        guard filterDate != nil, let filterDefaultsKey else { return }

        let saved = UserDefaults.standard.string(forKey: filterDefaultsKey)
        dateRange = NamedDateRange.options.contains(saved ?? "") ? saved : nil
    }

    /// Persists the chosen date filter, clearing it when no range is selected.
    func persistFilter() {
        guard let filterDefaultsKey else { return }

        if let dateRange {
            UserDefaults.standard.set(dateRange, forKey: filterDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: filterDefaultsKey)
        }
    }
}
