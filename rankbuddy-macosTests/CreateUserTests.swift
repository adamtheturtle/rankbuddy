//
//  CreateUserTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the create-user write flow (#58), driven through the demo server (the mock
/// acknowledges a POST to /users with a created record and 401s the bad-key token).
/// Serialized because the body-capture assertions read a shared static on the mock.
@MainActor
@Suite(.serialized)
struct CreateUserTests {
    private func makeClient(token: String = Account.demoToken) -> HackerRankClient {
        HackerRankClient(account: Account(label: "Demo", token: token))
    }

    @Test func `creating a user posts and decodes the created record`() async throws {
        let created = try await makeClient().createUser(email: "new@example.com", role: "recruiter")
        #expect(created.id == "u-created")
    }

    @Test func `the create body is snake-cased with the entered fields`() async throws {
        let path = "/x/api/v3/users"
        MockHackerRankURLProtocol.resetCapturedBody(forPath: path)
        _ = try await makeClient().createUser(
            email: "  new@example.com ", firstName: "New", lastName: "Person", role: "interviewer"
        )
        let body = try #require(MockHackerRankURLProtocol.lastRequestBody(forPath: path))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["email"] as? String == "new@example.com")
        #expect(json?["firstname"] as? String == "New")
        #expect(json?["lastname"] as? String == "Person")
        #expect(json?["role"] as? String == "interviewer")
    }

    @Test func `blank names are omitted from the body`() async throws {
        let path = "/x/api/v3/users"
        MockHackerRankURLProtocol.resetCapturedBody(forPath: path)
        _ = try await makeClient().createUser(email: "new@example.com", firstName: "   ", role: "recruiter")
        let body = try #require(MockHackerRankURLProtocol.lastRequestBody(forPath: path))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["firstname"] == nil)
    }

    @Test func `creating against the bad-key account surfaces the server's 401`() async {
        do {
            _ = try await HackerRankClient(account: .badKeyDemo).createUser(email: "new@example.com")
            Issue.record("expected an unauthorized error")
        } catch let error as HackerRankError {
            guard case let .http(status, _) = error else {
                Issue.record("expected .http, got \(error)")
                return
            }

            #expect(status == 401)
        } catch {
            Issue.record("expected HackerRankError, got \(error)")
        }
    }
}
