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
