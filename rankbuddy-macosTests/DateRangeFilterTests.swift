//
//  DateRangeFilterTests.swift
//  rankbuddy-macosTests
//

import BuddyAppKit
import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the list date-range filter (#19), driven with a fixed `now` so the
/// calendar-anchored windows are deterministic.
@MainActor
struct DateRangeFilterTests {
    private struct Row: Equatable {
        let id: Int
        let date: Date?
    }

    /// A stable reference instant well clear of a day boundary (12:00 UTC).
    private let now = Date(timeIntervalSince1970: 1_750_075_200)

    private func daysBefore(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
    }

    private func rows() -> [Row] {
        [
            Row(id: 0, date: now),
            Row(id: 1, date: daysBefore(3)),
            Row(id: 2, date: daysBefore(10)),
            Row(id: 3, date: daysBefore(100)),
            Row(id: 4, date: nil)
        ]
    }

    @Test func `a nil range keeps every item, including dateless ones`() {
        let result = DateRangeFilter.apply(rows(), range: nil, now: now) { $0.date }
        #expect(result.map(\.id) == [0, 1, 2, 3, 4])
    }

    @Test func `an unrecognised range imposes no constraint`() {
        let result = DateRangeFilter.apply(rows(), range: "since the dawn of time", now: now) { $0.date }
        #expect(result.count == 5)
    }

    @Test func `last 7 days keeps only recent dated items`() {
        let result = DateRangeFilter.apply(rows(), range: "last 7 days", now: now) { $0.date }
        // Today and 3 days ago are inside the window; 10/100 days ago and the dateless row drop.
        #expect(result.map(\.id) == [0, 1])
    }

    @Test func `a dateless item is dropped while a range is active`() {
        let result = DateRangeFilter.apply(rows(), range: "last 90 days", now: now) { $0.date }
        #expect(!result.contains { $0.id == 4 })
        // 100 days ago is still outside a 90-day window.
        #expect(!result.contains { $0.id == 3 })
        #expect(result.map(\.id) == [0, 1, 2])
    }

    @Test func `today keeps only items from the current calendar day`() {
        let result = DateRangeFilter.apply(rows(), range: "today", now: now) { $0.date }
        #expect(result.map(\.id) == [0])
    }

    // MARK: - Server-side value (#86)

    @Test func `no range yields no server value`() {
        #expect(DateRangeFilter.createdAtServerValue(nil, now: now) == nil)
        #expect(DateRangeFilter.createdAtServerValue("not a range", now: now) == nil)
    }

    @Test func `a named range becomes an ISO from..to value bounded by now`() throws {
        let value = try #require(DateRangeFilter.createdAtServerValue("last 7 days", now: now))
        let parts = value.components(separatedBy: "..")
        #expect(parts.count == 2)

        let formatter = ISO8601DateFormatter()
        let from = try #require(formatter.date(from: parts[0]))
        let upper = try #require(formatter.date(from: parts[1]))
        // Lower bound matches the named window's calendar-day start; upper bound is `now`.
        #expect(from == NamedDateRange.start(for: "last 7 days", now: now))
        #expect(upper == now)
        #expect(from < upper)
    }

    @Test func `today's server value starts at the calendar day, not 7 days back`() throws {
        let value = try #require(DateRangeFilter.createdAtServerValue("today", now: now))
        let formatter = ISO8601DateFormatter()
        let from = try #require(formatter.date(from: value.components(separatedBy: "..")[0]))
        #expect(from == Calendar.current.startOfDay(for: now))
    }
}
