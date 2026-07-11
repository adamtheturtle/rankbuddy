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
    private func makeClient(token: String = Account.demoToken) -> HackerRankClient {
        HackerRankClient(account: Account(label: "Demo", token: token))
    }

    @Test func `creating a user decodes the created record`() async throws {
        let created = try await makeClient().createUser(email: "new@example.com", role: "recruiter")
        #expect(created.id == "u-created")
    }

    @Test func `optional name fields are accepted`() async throws {
        // Blank optional fields are dropped by the client; the call still succeeds.
        let created = try await makeClient().createUser(
            email: "  new@example.com ", firstName: "   ", lastName: "Person", role: "interviewer"
        )
        #expect(created.id == "u-created")
    }

    @Test func `creating a user with a team decodes the created record`() async throws {
        let created = try await makeClient().createUser(
            email: "new@example.com", firstName: "New", lastName: nil, role: "recruiter", teamIDs: ["tm1"]
        )
        #expect(created?.id == "u-created")
    }

    @Test func `creating with a team against the bad-key account surfaces the 401`() async {
        do {
            _ = try await HackerRankClient(account: .badKeyDemo).createUser(
                email: "new@example.com", firstName: "New", lastName: nil, role: "recruiter", teamIDs: ["tm1"]
            )
            Issue.record("expected an unauthorized error")
        } catch let error as HackerRankError {
            #expect(error.isUnauthorized)
        } catch {
            Issue.record("expected HackerRankError, got \(error)")
        }
    }

    @Test func `creating against the bad-key account surfaces the server's 401`() async {
        do {
            _ = try await HackerRankClient(account: .badKeyDemo).createUser(email: "new@example.com")
            Issue.record("expected an unauthorized error")
        } catch let error as HackerRankError {
            #expect(error.isUnauthorized)
        } catch {
            Issue.record("expected HackerRankError, got \(error)")
        }
    }
}
