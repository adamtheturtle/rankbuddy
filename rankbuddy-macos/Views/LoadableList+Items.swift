//
//  LoadableList+Items.swift
//  rankbuddy-macos
//

import Foundation

/// The list's derived collections, split out of `LoadableList.swift` to keep that file within
/// the file-length budget. `extension` (internal), not `private extension`, so the view's body
/// in the other file can read them.
extension LoadableList {
    /// The items currently shown: filtered by search + date, then sorted (#19).
    var visibleItems: [Item] {
        let base = ListQuery.filtered(
            items, query: query, searchableText: searchableText, date: filterDate, dateRange: dateRange
        )
        let option = sortOptions.first { $0.id == sortSelection }
        return option.map { base.sorted(by: $0.areInIncreasingOrder) } ?? base
    }

    /// The selected, currently-visible items — the bulk CSV export's input (#44).
    var selectedItems: [Item] {
        visibleItems.filter { selection.contains($0.id) }
    }
}
