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
        self.name = Self.normalizedName(name)
        self.query = Self.normalizedQuery(query)
        self.dateRange = dateRange
        self.facets = facets.filter { !$0.value.isEmpty }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try Self.normalizedName(container.decode(String.self, forKey: .name))
        query = try Self.normalizedQuery(container.decode(String.self, forKey: .query))
        dateRange = try container.decodeIfPresent(String.self, forKey: .dateRange)
        // Older snapshots predate facet capture; default to none so they still decode.
        facets = try container.decodeIfPresent([String: [String]].self, forKey: .facets) ?? [:]
    }

    /// The facet selection as the `[String: Set<String>]` shape the live list binds to.
    var facetSelection: [String: Set<String>] {
        facets.mapValues(Set.init).filter { !$0.value.isEmpty }
    }

    /// Removes facet constraints the current list no longer declares. Saved searches outlive app
    /// versions, so renamed or removed facet IDs must not become invisible active state.
    func retainingFacetIDs(_ validIDs: Set<String>) -> Self {
        var validated = self
        validated.facets = facets.filter { validIDs.contains($0.key) && !$0.value.isEmpty }
        return validated
    }

    /// Clears a persisted range that the current app version no longer offers, preventing an
    /// invalid Picker selection from presenting as an active filter that constrains no rows.
    func retainingDateRanges(_ validRanges: Set<String>) -> Self {
        var validated = self
        if let dateRange, !validRanges.contains(dateRange) {
            validated.dateRange = nil
        }
        return validated
    }

    /// Whether this captures any constraint at all — an empty query, no range, and no facets
    /// would save nothing useful, so the UI refuses to create one.
    var isEmpty: Bool {
        query.isEmpty
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
        return query == Self.normalizedQuery(liveQuery)
            && dateRange == liveRange
            && facetSelection == normalizedLive
    }

    static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
    }

    static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedName(lhs)
        let right = normalizedName(rhs)
        return left.localizedCaseInsensitiveCompare(right) == .orderedSame
    }
}

/// Per-list persistence for saved searches, scoped by the list's restoration key so each
/// account/collection keeps its own (mirrors how favourites and filters are scoped).
enum SavedSearchStore {
    /// Per-list cap. The most recently saved searches are retained when older preferences exceed it.
    static let maximumCount = 20

    /// The `UserDefaults` key backing a list's saved searches.
    static func defaultsKey(for restorationKey: String) -> String {
        "savedsearch.\(restorationKey)"
    }

    static func recoveryKey(for restorationKey: String) -> String {
        "\(defaultsKey(for: restorationKey)).unreadable-backup"
    }

    /// Purges every collection's saved searches for an account whose backend identity changed.
    static func clear(accountID: UUID, defaults: UserDefaults = .standard) {
        let suffix = ".\(accountID.uuidString)"
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("savedsearch.")
            && (key.hasSuffix(suffix) || key.hasSuffix("\(suffix).unreadable-backup")) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Loads the saved searches for a list, or an empty array when none/unreadable.
    static func load(restorationKey: String, defaults: UserDefaults = .standard) -> [SavedSearch] {
        guard let data = defaults.data(forKey: defaultsKey(for: restorationKey)) else { return [] }

        if let searches = try? JSONDecoder().decode([SavedSearch].self, from: data) {
            let valid = validated(searches, restorationKey: restorationKey, defaults: defaults)
            if (try? JSONEncoder().encode(valid)) != data {
                save(valid, restorationKey: restorationKey, defaults: defaults)
            }
            return valid
        }

        // Keep the exact unreadable payload before recovering valid records independently. A
        // later save may replace the primary key, but never destroys the only recoverable copy.
        let recoveryKey = recoveryKey(for: restorationKey)
        if defaults.data(forKey: recoveryKey) == nil {
            defaults.set(data, forKey: recoveryKey)
        }

        guard let records = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }

        let recovered: [SavedSearch] = records.compactMap { record in
            guard JSONSerialization.isValidJSONObject(record),
                  let recordData = try? JSONSerialization.data(withJSONObject: record) else { return nil }

            return try? JSONDecoder().decode(SavedSearch.self, from: recordData)
        }
        return validated(recovered, restorationKey: restorationKey, defaults: defaults)
    }

    /// Persists the saved searches for a list, removing the key entirely when empty.
    static func save(_ searches: [SavedSearch], restorationKey: String, defaults: UserDefaults = .standard) {
        let key = defaultsKey(for: restorationKey)
        let limited = Array(searches.suffix(maximumCount))
        guard !limited.isEmpty, let data = try? JSONEncoder().encode(limited) else {
            defaults.removeObject(forKey: key)
            return
        }

        defaults.set(data, forKey: key)
    }

    private static func validated(
        _ searches: [SavedSearch],
        restorationKey: String,
        defaults: UserDefaults
    ) -> [SavedSearch] {
        var seen = Set<UUID>()
        var changed = searches.count > maximumCount
        let repaired = searches.map { search in
            guard seen.insert(search.id).inserted else {
                changed = true
                return SavedSearch(
                    name: search.name,
                    query: search.query,
                    dateRange: search.dateRange,
                    facets: search.facets
                )
            }

            return search
        }
        let limited = Array(repaired.suffix(maximumCount))
        if changed {
            save(limited, restorationKey: restorationKey, defaults: defaults)
        }
        return limited
    }
}
