//
//  TestWindowStatusTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for `Test.windowStatus(now:)` (the read-only window indicator). The reference
/// "now" is injected so the classification is deterministic.
@MainActor
struct TestWindowStatusTests {
    private func test(start: String? = nil, end: String? = nil) throws -> HackerRankKit.Test {
        var fields = [#""id":"t1""#, #""name":"T""#]
        if let start { fields.append("\"start_time\":\"\(start)\"") }
        if let end { fields.append("\"end_time\":\"\(end)\"") }
        let json = "{\(fields.joined(separator: ","))}"
        return try JSONDecoder().decode(HackerRankKit.Test.self, from: Data(json.utf8))
    }

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    private let start = "2026-05-01T09:00:00Z"
    private let end = "2026-06-01T09:00:00Z"

    @Test func `a future start is upcoming`() throws {
        let status = try test(start: start, end: end).windowStatus(now: date("2026-04-01T00:00:00Z"))
        #expect(status == .upcoming)
    }

    @Test func `a time inside the window is open`() throws {
        let status = try test(start: start, end: end).windowStatus(now: date("2026-05-15T00:00:00Z"))
        #expect(status == .open)
    }

    @Test func `a past end is closed`() throws {
        let status = try test(start: start, end: end).windowStatus(now: date("2026-07-01T00:00:00Z"))
        #expect(status == .closed)
    }

    @Test func `the exact end instant is closed`() throws {
        let status = try test(start: start, end: end).windowStatus(now: date(end))
        #expect(status == .closed)
    }

    @Test func `a one-sided window we are inside is open`() throws {
        // Only a start, already begun: open (ongoing).
        #expect(try test(start: start).windowStatus(now: date("2026-05-15T00:00:00Z")) == .open)
        // Only an end, still ahead: open.
        #expect(try test(end: end).windowStatus(now: date("2026-05-15T00:00:00Z")) == .open)
    }

    @Test func `no window yields no status`() throws {
        #expect(try test().windowStatus(now: date("2026-05-15T00:00:00Z")) == nil)
    }
}
