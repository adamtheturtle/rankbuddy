//
//  InviteCandidateTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the invite-candidate write flow (#12), driven through the in-process demo
/// server (`HackerRankClient.mock()`): a POST to `/tests/{id}/candidates` is acknowledged
/// with the canned created-candidate echo, and the bad-token account answers 401.
@MainActor
struct InviteCandidateTests {
    private func makeClient(token: String = Account.demoToken) -> HackerRankClient {
        HackerRankClient(account: Account(label: "Demo", token: token))
    }

    @Test func `inviting a candidate decodes the created record`() async throws {
        let created = try await makeClient().inviteCandidate(testID: "t1", email: "new@example.com")
        #expect(created.id == "c-invited")
    }

    @Test func `a blank full name and an email-less send still succeed`() async throws {
        // Optional fields: a blank name is dropped by the client and the email toggle off is a
        // valid request. The mock acknowledges either way.
        let created = try await makeClient().inviteCandidate(
            testID: "t1",
            email: "  trimmed@example.com  ",
            fullName: "   ",
            sendEmail: false
        )
        #expect(created.id == "c-invited")
    }

    @Test func `inviting against the bad-key account surfaces the server's 401`() async {
        do {
            _ = try await HackerRankClient(account: .badKeyDemo).inviteCandidate(testID: "t1", email: "new@example.com")
            Issue.record("expected an unauthorized error")
        } catch let error as HackerRankError {
            #expect(error.isUnauthorized)
        } catch {
            Issue.record("expected HackerRankError, got \(error)")
        }
    }
}
