//
//  LoadableList+FilterBar.swift
//  rankbuddy-macos
//

import BuddyAppKit
import BuddyDesignSystem
import SwiftUI

/// The filter bar shown above a `LoadableList`, modelled on PadBuddy's (#55/#25/#19). Two
/// wrapping rows sit between the list's title and its rows:
///
///  - `savedSearchesBar` — a row of rounded-rect recall tokens, one per saved search, applied on
///    tap and removed via their × (#25).
///  - `filterBar` — the per-field facet chips, the inline date-range chip, and the verb-style
///    `Save…` / `Clear` actions, all reflowing together as the pane narrows.
///
/// Both read the list's own filter state directly (rather than taking a dozen bindings), the same
/// way PadBuddy's `PadsView+FilterBar` extension is wired.
extension LoadableList {
    /// Whether any narrowing filter is currently set — drives the Save/Clear affordances.
    var hasActiveFilters: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || dateRange != nil
            || selectedFacets.contains { !$0.value.isEmpty }
    }

    /// Whether the facet/date/action row has anything to show, so an otherwise filter-less list
    /// (e.g. a merged collection) doesn't render an empty padded bar.
    var showsFilterBar: Bool {
        !facets.isEmpty || filterDate != nil || hasActiveFilters
    }

    // MARK: - Saved searches row

    @ViewBuilder var savedSearchesBar: some View {
        if !savedSearches.isEmpty {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(savedSearches) { search in
                    SavedSearchChip(
                        name: search.name,
                        isActive: search.matches(query: query, dateRange: dateRange, facets: selectedFacets)
                    ) {
                        apply(search)
                    } onDelete: {
                        deleteSavedSearch(search)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, 6)
        }
    }

    // MARK: - Facet + date + actions row

    @ViewBuilder var filterBar: some View {
        if showsFilterBar {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(facets) { facet in
                    facetChip(facet)
                }

                if filterDate != nil {
                    FilterChipMenu(
                        title: dateFilterLabel,
                        icon: "calendar",
                        selected: $dateRange,
                        options: NamedDateRange.options,
                        formatter: { DisplayFormat.enumLabel($0) }
                    )
                    .help("Filter \(title) by date")
                }

                // Save the live filter set as a recall token. A link, so it reads as a verb rather
                // than another neutral filter chip. Only persisted lists can save (#25).
                if restorationKey != nil, hasActiveFilters {
                    Button {
                        newSearchName = ""
                        isNamingSearch = true
                    } label: {
                        Label("Save…", systemImage: "bookmark")
                            .labelStyle(.titleAndIcon)
                    }
                    .linkButtonStyle()
                    .controlSize(.small)
                    .help("Save the current filters as a search you can re-apply")
                }

                if hasActiveFilters {
                    Button(role: .destructive) {
                        clearAllFilters()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Clear all filters")
                }
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            // Leading-align against the window edge, matching PadBuddy's filter bar; without this
            // the flow centres a partly-filled row in the column, which reads as unpolished (#109).
            .frame(maxWidth: .infinity, alignment: .leading)
            .alert("Save Search", isPresented: $isNamingSearch) {
                TextField("Name", text: $newSearchName)
                Button("Cancel", role: .cancel) {}
                Button(existingNamedSearch == nil ? "Save" : "Replace") { saveCurrentSearch() }
                    .disabled(trimmedSearchName.isEmpty)
            } message: {
                if let existingNamedSearch {
                    Text("Replace “\(existingNamedSearch.name)” with the current filters?")
                } else {
                    Text("Save the current filters so you can re-apply them later.")
                }
            }
        }
    }

    // MARK: - Facet chip (PadBuddy's capsule vocabulary)

    private func facetChip(_ facet: ListFacet<Item>) -> some View {
        let options = ListQuery.facetOptions(facet, in: items)
        let chosen = selectedFacets[facet.id] ?? []
        let isActive = !chosen.isEmpty
        return ChipMenuShell(
            icon: facet.systemImage,
            text: facetChipText(facet, chosen: chosen),
            isActive: isActive,
            fillColor: isActive ? Color.accentColor.opacity(0.18) : .chipIdleFill,
            strokeColor: isActive ? Color.accentColor.opacity(0.4) : .subtleStroke,
            labelColor: chipLabelColor(isActive: isActive),
            menuDisabled: options.isEmpty,
            clearLabel: "Clear \(facet.label) filter",
            onClear: { selectedFacets[facet.id] = [] },
            menu: {
                // Multi-select: each value is a toggle, so several can be active at once.
                ForEach(options, id: \.self) { option in
                    Toggle(isOn: facetBinding(facet.id, option)) { Text(option) }
                }
            }
        )
        .help("Filter by \(facet.label.lowercased())")
    }

    /// Label PadBuddy-style: a single chosen value reads as itself (e.g. "Active"), so the chip
    /// states the filter at a glance; two-plus values fall back to a "Label (N)" count because
    /// listing them would overflow the chip; an idle facet just shows its label.
    private func facetChipText(_ facet: ListFacet<Item>, chosen: Set<String>) -> String {
        if chosen.count == 1, let only = chosen.first {
            return only
        }
        if chosen.count > 1 {
            return "\(facet.label) (\(chosen.count))"
        }
        return facet.label
    }

    private func facetBinding(_ facetID: String, _ option: String) -> Binding<Bool> {
        Binding(
            get: { selectedFacets[facetID]?.contains(option) ?? false },
            set: { isOn in
                var set = selectedFacets[facetID] ?? []
                if isOn { set.insert(option) } else { set.remove(option) }
                selectedFacets[facetID] = set
            }
        )
    }

    // MARK: - Saved-search actions

    private var trimmedSearchName: String {
        newSearchName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var existingNamedSearch: SavedSearch? {
        savedSearches.first { SavedSearch.namesMatch($0.name, trimmedSearchName) }
    }

    /// Loads the saved searches for the current list into state (#25). Called on appear and when
    /// the account-scoped restoration key changes, so each account shows its own.
    func loadSavedSearches() {
        guard let restorationKey else {
            savedSearches = []
            return
        }

        let loaded = SavedSearchStore.load(restorationKey: restorationKey)
        let validFacetIDs = Set(facets.map(\.id))
        let validDateRanges = Set(NamedDateRange.options)
        let validated = loaded.map {
            $0.retainingFacetIDs(validFacetIDs).retainingDateRanges(validDateRanges)
        }
        savedSearches = validated
        if validated != loaded {
            SavedSearchStore.save(validated, restorationKey: restorationKey)
        }
    }

    /// Applies a saved search's full filter set to the live list (#25).
    private func apply(_ search: SavedSearch) {
        query = search.query
        let validated = search
            .retainingFacetIDs(Set(facets.map(\.id)))
            .retainingDateRanges(Set(NamedDateRange.options))
        dateRange = validated.dateRange
        selectedFacets = validated.facetSelection
    }

    /// Captures the live filters as a named search and persists it (#25). No-ops for unpersisted
    /// lists or an empty/name-less capture, which the UI already guards against.
    private func saveCurrentSearch() {
        guard let restorationKey else { return }

        let name = trimmedSearchName
        let existing = existingNamedSearch
        let search = SavedSearch(
            name: name,
            query: query,
            dateRange: dateRange,
            facets: selectedFacets.mapValues(Array.init),
            id: existing?.id ?? UUID()
        )
        guard !name.isEmpty, !search.isEmpty else { return }

        let updated = savedSearches.map { $0.id == existing?.id ? search : $0 }
        let retained = Array((existing == nil ? updated + [search] : updated).suffix(SavedSearchStore.maximumCount))
        replaceSavedSearches(retained, restorationKey: restorationKey, actionName: "Save Search")
    }

    private func deleteSavedSearch(_ search: SavedSearch) {
        guard let restorationKey else { return }

        replaceSavedSearches(
            savedSearches.filter { $0.id != search.id },
            restorationKey: restorationKey,
            actionName: "Delete Saved Search"
        )
    }

    private func replaceSavedSearches(
        _ searches: [SavedSearch],
        restorationKey: String,
        actionName: String
    ) {
        let previous = savedSearches
        guard previous != searches else { return }

        savedSearches = searches
        SavedSearchStore.save(searches, restorationKey: restorationKey)
        undoManager?.registerUndo(withTarget: UndoAction {
            replaceSavedSearches(previous, restorationKey: restorationKey, actionName: actionName)
        }) { target in
            target.perform()
        }
        undoManager?.setActionName(actionName)
    }

    /// Clears every narrowing filter at once — the bar's Clear action (#55).
    func clearAllFilters() {
        query = ""
        dateRange = nil
        selectedFacets = [:]
    }
}
