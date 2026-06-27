//
//  ListFacet.swift
//  rankbuddy-macos
//

import Foundation

/// A declarative filter facet for `LoadableList` (#55): a named field whose distinct values
/// become a multi-select dropdown in the facet bar. Each screen lists its own facets the way
/// it lists `sortOptions`. `values` returns the item's value(s) for the facet — one element for
/// a scalar field (state, status, role) or several for a list field (languages, tags) — so a
/// single closure shape covers both. Empty strings are ignored.
struct ListFacet<Item>: Identifiable {
    let id: String
    let label: String
    let systemImage: String
    let values: (Item) -> [String]

    init(
        _ id: String,
        _ label: String,
        systemImage: String = "line.3.horizontal.decrease.circle",
        values: @escaping (Item) -> [String]
    ) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.values = values
    }

    /// Convenience for a scalar facet whose value is a single optional string.
    init(
        _ id: String,
        _ label: String,
        systemImage: String = "line.3.horizontal.decrease.circle",
        value: @escaping (Item) -> String?
    ) {
        self.init(id, label, systemImage: systemImage) { value($0).map { [$0] } ?? [] }
    }
}
