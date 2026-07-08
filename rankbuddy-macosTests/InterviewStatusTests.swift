//
//  InterviewStatusTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for `Interview.statusBadge` — the lifecycle pill shown in the interviews list.
@MainActor
struct InterviewStatusTests {
    private func interview(status: String) throws -> Interview {
        let json = #"{"id":"i1","status":"\#(status)","url":"https://example.com/i1"}"#
        return try JSONDecoder().decode(Interview.self, from: Data(json.utf8))
    }

    @Test func `known statuses get a friendly label`() throws {
        #expect(try interview(status: "completed").statusBadge.text == "Completed")
        #expect(try interview(status: "scheduled").statusBadge.text == "Scheduled")
        #expect(try interview(status: "in_progress").statusBadge.text == "In progress")
        #expect(try interview(status: "cancelled").statusBadge.text == "Cancelled")
    }

    @Test func `matching is case-insensitive`() throws {
        #expect(try interview(status: "Completed").statusBadge.text == "Completed")
    }

    @Test func `an unknown status falls back to the capitalised raw value`() throws {
        #expect(try interview(status: "archived").statusBadge.text == "Archived")
    }
}
