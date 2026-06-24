import SwiftUI

/// The state of an asynchronous load.
enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(String)
}

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

/// A list that loads its items asynchronously and renders loading, empty, and error
/// states, with search, optional sorting, and a refresh action. Each row pushes a detail
/// view through the enclosing `NavigationStack`.
struct LoadableList<Item: Identifiable & Hashable, Row: View, Detail: View>: View {
    let title: String
    let emptyMessage: String
    let load: () async throws -> [Item]
    /// The text a row is matched against when filtering by the search field.
    let searchableText: (Item) -> String
    /// The ways the list can be ordered; the first is the default. Empty hides the menu.
    var sortOptions: [SortOption<Item>] = []
    /// When set, the list owns its `NavigationStack` and restores/persists the selected
    /// item across launches under this key (#19). Callers scope the key by account and
    /// collection. `nil` (e.g. a list nested inside another stack) disables both.
    var restorationKey: String?
    @ViewBuilder let row: (Item) -> Row
    @ViewBuilder let detail: (Item) -> Detail

    @State private var state: LoadState<[Item]> = .loading
    @State private var query = ""
    @State private var sortSelection: SortOption<Item>.ID?
    /// The pushed-detail navigation path; only used (and bound) when `restorationKey` is set.
    @State private var path: [Item] = []
    /// Guards selection restoration to once per load cycle, so navigating back doesn't re-push.
    @State private var didRestore = false

    var body: some View {
        if restorationKey != nil {
            NavigationStack(path: $path) { core }
        } else {
            core
        }
    }

    private var core: some View {
        content
            .navigationTitle(title)
            .navigationDestination(for: Item.self, destination: detail)
            .searchable(text: $query, placement: .sidebar, prompt: "Search \(title)")
            .toolbar {
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
            .task(id: restorationKey) {
                didRestore = false
                path = []
                await reload()
            }
            .onAppear { restoreSort() }
            .onChange(of: sortSelection) { persistSort() }
            .onChange(of: path) { persistSelection() }
    }

    /// Where this list's chosen sort order is remembered between launches (#19). Keyed by
    /// title, so each collection keeps its own preference.
    private var sortDefaultsKey: String {
        "sort.\(title)"
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
        switch state {
        case .loading:
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .loaded(items) where items.isEmpty:
            ContentUnavailableView(emptyMessage, systemImage: "tray")

        case let .loaded(items):
            loadedList(items)

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

    @ViewBuilder private func loadedList(_ items: [Item]) -> some View {
        let visible = sort(filter(items))
        if visible.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                ForEach(visible) { item in
                    NavigationLink(value: item) { row(item) }
                }
            }
            .navigationSubtitle("\(visible.count) \(visible.count == 1 ? "item" : "items")")
        }
    }

    private func filter(_ items: [Item]) -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        return items.filter { searchableText($0).localizedCaseInsensitiveContains(trimmed) }
    }

    private func sort(_ items: [Item]) -> [Item] {
        guard let option = sortOptions.first(where: { $0.id == sortSelection }) else { return items }

        return items.sorted(by: option.areInIncreasingOrder)
    }

    private var isLoading: Bool {
        if case .loading = state { true } else { false }
    }

    private func reload() async {
        state = .loading
        do {
            let items = try await load()
            state = .loaded(items)
            restoreSelectionIfNeeded(items)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .failed(message)
        }
    }

    /// Re-opens the last-viewed item's detail once per load, if it still exists. A missing
    /// item (deleted, or a different account) simply leaves the list at the top — no loops,
    /// no blank pane (#19).
    private func restoreSelectionIfNeeded(_ items: [Item]) {
        guard let restorationKey, !didRestore, path.isEmpty else { return }

        didRestore = true
        guard let stored = UserDefaults.standard.string(forKey: restorationKey),
              let item = items.first(where: { String(describing: $0.id) == stored })
        else { return }

        path = [item]
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
