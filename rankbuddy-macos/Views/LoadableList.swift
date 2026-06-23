import SwiftUI

/// The state of an asynchronous load.
enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(String)
}

/// A list that loads its items asynchronously and renders loading, empty, and error
/// states, with search and a refresh action. Each row pushes a detail view through the
/// enclosing `NavigationStack`.
struct LoadableList<Item: Identifiable & Hashable, Row: View, Detail: View>: View {
    let title: String
    let emptyMessage: String
    let load: () async throws -> [Item]
    /// The text a row is matched against when filtering by the search field.
    let searchableText: (Item) -> String
    @ViewBuilder let row: (Item) -> Row
    @ViewBuilder let detail: (Item) -> Detail

    @State private var state: LoadState<[Item]> = .loading
    @State private var query = ""

    var body: some View {
        content
            .navigationTitle(title)
            .navigationDestination(for: Item.self, destination: detail)
            .searchable(text: $query, placement: .sidebar, prompt: "Search \(title)")
            .toolbar {
                Button {
                    Task { await reload() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
            .task { await reload() }
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
        let filtered = filter(items)
        if filtered.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                ForEach(filtered) { item in
                    NavigationLink(value: item) { row(item) }
                }
            }
        }
    }

    private func filter(_ items: [Item]) -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        return items.filter { searchableText($0).localizedCaseInsensitiveContains(trimmed) }
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
