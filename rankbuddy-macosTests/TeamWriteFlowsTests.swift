//
//  TeamWriteFlowsTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the team write flows (#59) — create a team and add/remove members — driven
/// through the in-process demo server (`HackerRankClient.mock()`): a POST is acknowledged
/// with the canned echo, a DELETE with a 200, and the bad-token account answers 401.
@MainActor
struct TeamWriteFlowsTests {
    @Test func `team names respect the API limit`() {
        #expect(TeamNameValidation.isValid("Platform"))
        #expect(!TeamNameValidation.isValid(String(repeating: "x", count: 256)))
    }

    @Test func `team lists preserve first spelling and remove logical duplicates`() {
        #expect(TeamFieldValidation.normalizedList(
            " London, london, LONDON, New York, new york "
        ) == ["London", "New York"])
        #expect(TeamFieldValidation.normalizedList(" , ") == nil)
    }

    private func makeClient(token: String = Account.demoToken) -> HackerRankClient {
        HackerRankClient(account: Account(label: "Demo", token: token))
    }

    @Test func `creating a team decodes the created record`() async throws {
        let created = try await makeClient().createTeam(name: "  Platform Hiring  ")
        #expect(created.id == "tm-created")
    }

    @Test func `adding a member decodes the membership record`() async throws {
        let created = try await makeClient().createUser(
            email: " new@example.com ",
            firstName: "New",
            role: "developer",
            teamIDs: ["tm1"]
        )
        #expect(created.id == "u-created")
    }

    @Test func `removing a member succeeds against the demo without throwing`() async throws {
        try await makeClient().removeTeamMember(teamID: "tm1", userID: "u2")
    }

    @Test func `team writes against the bad-key account surface the server's 401`() async {
        let client = HackerRankClient(account: .badKeyDemo)
        await expectUnauthorized {
            _ = try await client.createTeam(name: "Nope")
        }
        await expectUnauthorized {
            _ = try await client.removeTeamMember(teamID: "tm1", userID: "u2")
        }
    }
}
