import BuddyAppKit
import Foundation

/// Applies a named date-range filter to a list, built on buddy-kit's `DateWindow`
/// windowing (#19). The list views offer the ranges in `NamedDateRange.options` (e.g.
/// "last 7 days") as a filter chip; this is the pure predicate behind it, kept out of the
/// view so it can be tested with an injected `now`.
enum DateRangeFilter {
    /// Keeps the items whose `date` falls within the named `range`. While a range is
    /// active, items with no date are dropped (they can't satisfy a date window). A `nil`
    /// or unrecognised range imposes no constraint and returns everything.
    static func apply<Item>(
        _ items: [Item],
        range: String?,
        now: Date = Date(),
        date: (Item) -> Date?
    ) -> [Item] {
        guard let range, NamedDateRange.options.contains(range) else { return items }

        let window = DateWindow(range: range)
        return items.filter { item in
            guard let value = date(item) else { return false }

            return window.contains(value, now: now)
        }
    }
}
