//
//  SavedSearch.swift
//  rankbuddy-macos
//

import Foundation

/// A named, reusable combination of a list's free-text query, date-range, and facet filters
/// (#25), so a recruiter can re-run "last 7 days, failed, JavaScript" without re-entering it.
///
/// Sort is deliberately not captured: it's a presentation preference already persisted on
/// its own, whereas a saved search is about *which* rows are shown.
nonisolated struct SavedSearch: Codable, Identifiable, Hashable {
    /// The longest a saved-search name may be. Names are short recall labels shown as chips, so
    /// capping them keeps any one chip from dominating the bar and guards against an accidental
    /// paste of a huge string; the chip also clamps display for names persisted before the cap.
    static let maxNameLength = 40

    let id: UUID
    var name: String
    /// The free-text query, or empty for none.
    var query: String
    /// The selected date-range option (one of `NamedDateRange.options`), or `nil`.
    var dateRange: String?
    /// The chosen facet values keyed by facet id (#55), stored as arrays so the snapshot is
    /// plain `Codable`. Empty when the search carries no facet constraint. Optional on decode so
    /// snapshots saved before facets were captured still load.
    var facets: [String: [String]]

    init(name: String, query: String, dateRange: String?, facets: [String: [String]] = [:], id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.query = query
        self.dateRange = dateRange
        self.facets = facets.filter { !$0.value.isEmpty }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        query = try container.decode(String.self, forKey: .query)
        dateRange = try container.decodeIfPresent(String.self, forKey: .dateRange)
        // Older snapshots predate facet capture; default to none so they still decode.
        facets = try container.decodeIfPresent([String: [String]].self, forKey: .facets) ?? [:]
    }

    /// The facet selection as the `[String: Set<String>]` shape the live list binds to.
    var facetSelection: [String: Set<String>] {
        facets.mapValues(Set.init).filter { !$0.value.isEmpty }
    }

    /// Whether this captures any constraint at all — an empty query, no range, and no facets
    /// would save nothing useful, so the UI refuses to create one.
    var isEmpty: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && dateRange == nil
            && facets.values.allSatisfy(\.isEmpty)
    }

    /// Whether the live filter state (query, date range, facet selection) exactly matches this
    /// saved search, so its chip can show as applied. Empty per-facet sets are ignored on both
    /// sides so a cleared facet never causes a spurious mismatch.
    func matches(
        query liveQuery: String,
        dateRange liveRange: String?,
        facets liveFacets: [String: Set<String>]
    ) -> Bool {
        let normalizedLive = liveFacets.filter { !$0.value.isEmpty }
        return query == liveQuery && dateRange == liveRange && facetSelection == normalizedLive
    }
}

/// Per-list persistence for saved searches, scoped by the list's restoration key so each
/// account/collection keeps its own (mirrors how favourites and filters are scoped).
enum SavedSearchStore {
    /// The `UserDefaults` key backing a list's saved searches.
    static func defaultsKey(for restorationKey: String) -> String {
        "savedsearch.\(restorationKey)"
    }

    /// Loads the saved searches for a list, or an empty array when none/unreadable.
    static func load(restorationKey: String, defaults: UserDefaults = .standard) -> [SavedSearch] {
        guard let data = defaults.data(forKey: defaultsKey(for: restorationKey)),
              let searches = try? JSONDecoder().decode([SavedSearch].self, from: data)
        else { return [] }

        return searches
    }

    /// Persists the saved searches for a list, removing the key entirely when empty.
    static func save(_ searches: [SavedSearch], restorationKey: String, defaults: UserDefaults = .standard) {
        let key = defaultsKey(for: restorationKey)
        guard !searches.isEmpty, let data = try? JSONEncoder().encode(searches) else {
            defaults.removeObject(forKey: key)
            return
        }

        defaults.set(data, forKey: key)
    }
}
