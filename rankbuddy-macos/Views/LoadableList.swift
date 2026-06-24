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
    @ViewBuilder let row: (Item) -> Row
    @ViewBuilder let detail: (Item) -> Detail

    @State private var state: LoadState<[Item]> = .loading
    @State private var query = ""
    @State private var sortSelection: SortOption<Item>.ID?

    var body: some View {
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
            .task { await reload() }
            .onAppear {
                if sortSelection == nil { sortSelection = sortOptions.first?.id }
            }
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
            state = try await .loaded(load())
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .failed(message)
        }
    }
}
