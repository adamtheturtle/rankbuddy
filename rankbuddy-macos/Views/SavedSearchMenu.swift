//
//  SavedSearchMenu.swift
//  rankbuddy-macos
//

import SwiftUI

/// The toolbar menu for applying, saving, and deleting a list's saved searches (#25).
///
/// Owns its own persisted list (loaded on appear, keyed by the host list's `restorationKey`)
/// and reaches the live query and date filter through bindings, so applying a saved search
/// updates the list and saving one captures its current state. Kept separate from
/// `LoadableList` so the list shell stays focused on loading and paging.
struct SavedSearchMenu: View {
    let title: String
    let restorationKey: String
    @Binding var query: String
    @Binding var dateRange: String?

    @State private var savedSearches: [SavedSearch] = []
    @State private var isNaming = false
    @State private var newName = ""

    var body: some View {
        Menu {
            if savedSearches.isEmpty {
                Text("No saved searches")
            } else {
                ForEach(savedSearches) { search in
                    Button(search.name) { apply(search) }
                }
                Divider()
                Menu("Delete Saved Search") {
                    ForEach(savedSearches) { search in
                        Button(search.name, role: .destructive) { delete(search) }
                    }
                }
            }

            Divider()
            Button("Save Current Search…") { beginNaming() }
                .disabled(currentSearchIsEmpty)
        } label: {
            Label("Saved Searches", systemImage: "bookmark")
        }
        .help("Saved searches for \(title)")
        .onAppear { savedSearches = SavedSearchStore.load(restorationKey: restorationKey) }
        .alert("Save Search", isPresented: $isNaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveCurrent() }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Save the current search and date filter so you can re-apply it later.")
        }
    }

    /// Whether the current query and date filter are both empty — nothing worth saving.
    private var currentSearchIsEmpty: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && dateRange == nil
    }

    /// Applies a saved search's query and date filter to the live list.
    private func apply(_ search: SavedSearch) {
        query = search.query
        dateRange = search.dateRange
    }

    private func beginNaming() {
        newName = ""
        isNaming = true
    }

    private func saveCurrent() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let search = SavedSearch(name: name, query: query, dateRange: dateRange)
        guard !name.isEmpty, !search.isEmpty else { return }

        savedSearches.append(search)
        SavedSearchStore.save(savedSearches, restorationKey: restorationKey)
    }

    private func delete(_ search: SavedSearch) {
        savedSearches.removeAll { $0.id == search.id }
        SavedSearchStore.save(savedSearches, restorationKey: restorationKey)
    }
}
