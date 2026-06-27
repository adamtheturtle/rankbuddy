//
//  DateRangeFilter.swift
//  rankbuddy-macos
//

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

    /// The value for a server-side `created_at=<from>..<to>` filter equivalent to the named
    /// `range`, or `nil` when no/unknown range is active (#86). Used for large collections (e.g.
    /// the 87k-interview org) where the client-side `apply` above can only see loaded rows, so the
    /// server must do the filtering. The bounds match `NamedDateRange`'s calendar-day semantics:
    /// the lower bound is the named window's start and the upper bound is `now`. Formatted as
    /// ISO-8601 UTC (`…Z`), which the HackerRank API accepts.
    static func createdAtServerValue(_ range: String?, now: Date = Date()) -> String? {
        guard let range, let start = NamedDateRange.start(for: range, now: now) else { return nil }

        let formatter = ISO8601DateFormatter()
        return "\(formatter.string(from: start))..\(formatter.string(from: now))"
    }
}
