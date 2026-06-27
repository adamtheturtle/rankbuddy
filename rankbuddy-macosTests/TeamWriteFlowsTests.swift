//
//  TeamWriteFlowsTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the team write flows (#59) — create a team and add/remove members — driven
/// through the demo server (a POST is acknowledged with a created record, a DELETE with a
/// 200, and the bad-key token 401s). Serialized because the body-capture assertions read a
/// shared static on the mock.
@MainActor
@Suite(.serialized)
struct TeamWriteFlowsTests {
    private func makeClient(token: String = Account.demoToken) -> HackerRankClient {
        HackerRankClient(account: Account(label: "Demo", token: token))
    }

    @Test func `creating a team posts the name and decodes the created record`() async throws {
        let path = "/x/api/v3/teams"
        MockHackerRankURLProtocol.resetCapturedBody(forPath: path)
        let created = try await makeClient().createTeam(name: "  Platform Hiring  ")
        #expect(created.id == "tm-created")

        let body = try #require(MockHackerRankURLProtocol.lastRequestBody(forPath: path))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        // The name is trimmed before sending.
        #expect(json?["name"] as? String == "Platform Hiring")
    }

    @Test func `adding a member posts the email and role under the team`() async throws {
        let path = "/x/api/v3/teams/tm1/users"
        MockHackerRankURLProtocol.resetCapturedBody(forPath: path)
        let result = try await makeClient().addTeamMember(teamID: "tm1", email: " new@example.com ", role: "developer")
        // The membership path contains "/users", so the mock acknowledges with a user record.
        #expect(result.id == "u-created")

        let body = try #require(MockHackerRankURLProtocol.lastRequestBody(forPath: path))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["email"] as? String == "new@example.com")
        #expect(json?["role"] as? String == "developer")
    }

    @Test func `a blank role is omitted when adding a member`() async throws {
        let path = "/x/api/v3/teams/tm1/users"
        MockHackerRankURLProtocol.resetCapturedBody(forPath: path)
        _ = try await makeClient().addTeamMember(teamID: "tm1", email: "new@example.com", role: "   ")
        let body = try #require(MockHackerRankURLProtocol.lastRequestBody(forPath: path))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["role"] == nil)
    }

    @Test func `removing a member deletes against the demo without throwing`() async throws {
        // The user is identified in the path; a 2xx is enough to confirm the wiring.
        let result = try await makeClient().removeTeamMember(teamID: "tm1", userID: "u2")
        #expect(result.id == "u-created")
    }

    @Test func `team writes against the bad-key account surface the server's 401`() async {
        let client = HackerRankClient(account: .badKeyDemo)
        await #expect(throws: HackerRankError.self) {
            try await client.createTeam(name: "Nope")
        }
        await #expect(throws: HackerRankError.self) {
            try await client.removeTeamMember(teamID: "tm1", userID: "u2")
        }
    }
}
