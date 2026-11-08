//
//  CreateUserTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the create-user write flow (#58), driven through the in-process demo server
/// (`HackerRankClient.mock()`): the mock acknowledges a POST to /users with the canned echo
/// and 401s the bad-token account.
@MainActor
struct CreateUserTests {
    @Test func `user names respect API limits`() {
        #expect(UserNameValidation.firstNameIssue("   ") == "First name is required.")
        #expect(UserNameValidation.firstNameIssue(String(repeating: "x", count: 255)) == nil)
        #expect(UserNameValidation.firstNameIssue(String(repeating: "x", count: 256)) != nil)
        #expect(UserNameValidation.lastNameIssue(String(repeating: "x", count: 255)) == nil)
        #expect(UserNameValidation.lastNameIssue(String(repeating: "x", count: 256)) != nil)
        #expect(UserNameValidation.issue(
            firstName: String(repeating: "x", count: 256),
            lastName: nil
        )?.contains("First name") == true)
        #expect(UserNameValidation.issue(
            firstName: "Ada",
            lastName: String(repeating: "x", count: 256)
        )?.contains("Last name") == true)
    }

    private func makeClient(token: String = Account.demoToken) -> HackerRankClient {
        HackerRankClient(account: Account(label: "Demo", token: token))
    }

    @Test func `creating a user decodes the created record`() async throws {
        let created = try await makeClient().createUser(
            email: "new@example.com",
            firstName: "New",
            role: "recruiter",
            teamIDs: ["tm1"]
        )
        #expect(created.id == "u-created")
    }

    @Test func `blank first names are rejected before the request is sent`() async {
        await #expect(throws: HackerRankError.self) {
            _ = try await makeClient().createUser(
                email: "new@example.com", firstName: "   ", role: "interviewer", teamIDs: ["tm1"]
            )
        }
    }

    @Test func `creating a user with a team decodes the created record`() async throws {
        let created = try await makeClient().createUser(
            email: "new@example.com", firstName: "New", role: "recruiter", teamIDs: ["tm1"]
        )
        #expect(created.id == "u-created")
    }

    @Test func `creating with a team against the bad-key account surfaces the 401`() async {
        await expectUnauthorized {
            _ = try await HackerRankClient(account: .badKeyDemo).createUser(
                email: "new@example.com", firstName: "New", role: "recruiter", teamIDs: ["tm1"]
            )
        }
    }

    @Test func `creating against the bad-key account surfaces the server's 401`() async {
        await expectUnauthorized {
            _ = try await HackerRankClient(account: .badKeyDemo).createUser(
                email: "new@example.com",
                firstName: "New",
                role: "recruiter",
                teamIDs: ["tm1"]
            )
        }
    }
}
