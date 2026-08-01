//
//  InterviewWriteFlowsTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the interview write flows (#60) — create a Pad and schedule an
/// interview — driven through the in-process demo server (`HackerRankClient.mock()`): a POST
/// is acknowledged with the canned interview echo and the bad-token account answers 401.
@MainActor
struct InterviewWriteFlowsTests {
    @Test func `pad titles normalize and respect the API limit`() {
        #expect(PadTitleValidation.normalized("  Pairing Pad  ") == "Pairing Pad")
        #expect(PadTitleValidation.normalized(" \n ") == nil)
        #expect(PadTitleValidation.normalized(String(repeating: "x", count: 300))?.count
            == PadTitleValidation.maxLength)
    }

    @Test func `scheduled interview text respects payload limits`() {
        #expect(InterviewScheduleValidation.textIssue(
            title: String(repeating: "x", count: 256),
            candidateEmail: nil,
            notes: nil
        )?.contains("Title") == true)
        #expect(InterviewScheduleValidation.textIssue(
            title: "Pairing",
            candidateEmail: nil,
            notes: String(repeating: "x", count: 10001)
        )?.contains("Notes") == true)
        #expect(InterviewScheduleValidation.titleIssue(String(repeating: "x", count: 256)) != nil)
        #expect(InterviewScheduleValidation.titleIssue(String(repeating: "x", count: 255)) == nil)
        #expect(InterviewScheduleValidation.notesIssue(String(repeating: "x", count: 10001)) != nil)
        #expect(InterviewScheduleValidation.notesIssue(String(repeating: "x", count: 10000)) == nil)
    }

    @Test func `scheduled interviews require a future start`() {
        let now = Date(timeIntervalSince1970: 1000)

        #expect(InterviewScheduleValidation.dateIssue(start: now, now: now) != nil)
        #expect(InterviewScheduleValidation.dateIssue(
            start: now.addingTimeInterval(1), now: now
        ) == nil)
    }

    private func makeClient(token: String = Account.demoToken) -> HackerRankClient {
        HackerRankClient(account: Account(label: "Demo", token: token))
    }

    @Test func `creating a Pad decodes the created record`() async throws {
        let created = try await makeClient().createPad(title: "  Pairing Pad  ")
        #expect(created.id == "i-created")
        #expect(created.url?.contains("i-created") == true)
    }

    @Test func `a blank Pad title still succeeds via the client's default`() async throws {
        // The API rejects a titleless interview with HTTP 400 (#83); the client substitutes a
        // dated default, so a blank title is accepted.
        let created = try await makeClient().createPad(title: "   ")
        #expect(created.id == "i-created")
    }

    @Test func `a real Pad response requires a valid web URL before completion`() throws {
        #expect(try padDestinationURL(rawURL: "https://example.com/pads/1", isMock: false) != nil)
        #expect(throws: MissingPadURL.self) {
            try padDestinationURL(rawURL: nil, isMock: false)
        }
        #expect(throws: MissingPadURL.self) {
            try padDestinationURL(rawURL: "file:///tmp/pad", isMock: false)
        }
        #expect(try padDestinationURL(rawURL: nil, isMock: true) == nil)
    }

    @Test func `scheduling an interview decodes the created record`() async throws {
        let created = try await makeClient().scheduleInterview(
            title: "  Backend Screen  ",
            from: Date(timeIntervalSince1970: 1_750_000_000),
            candidateEmail: " ada@example.com ",
            notes: "  Focus on systems design  "
        )
        #expect(created.id == "i-created")
    }

    @Test func `interview writes against the bad-key account surface the server's 401`() async {
        let client = HackerRankClient(account: .badKeyDemo)
        await #expect(throws: HackerRankError.self) {
            try await client.createPad(title: "Nope")
        }
        await #expect(throws: HackerRankError.self) {
            try await client.scheduleInterview(title: "Nope", from: Date(timeIntervalSince1970: 0))
        }
    }
}
