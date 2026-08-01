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
    @Test func `template pagination rejects empty and repeated pages`() throws {
        var seen: Set<String> = []
        #expect(try InviteTemplatePaging.next("c1", itemCount: 1, seen: &seen) == "c1")
        #expect(throws: InviteTemplatePaging.NoProgress.self) {
            try InviteTemplatePaging.next("c1", itemCount: 1, seen: &seen)
        }
        #expect(throws: InviteTemplatePaging.NoProgress.self) {
            try InviteTemplatePaging.next("c2", itemCount: 0, seen: &seen)
        }
    }

    @Test func `template pagination keeps the first unique stable identity`() {
        let incoming = [(id: String?.some("a"), name: "First"), (id: "a", name: "Duplicate"),
                        (id: nil, name: "Missing"), (id: "b", name: "Second")]
        var loaded: [(id: String?, name: String)] = []
        var seen: Set<String> = []

        InviteTemplatePaging.appendUnique(incoming, to: &loaded, seenIDs: &seen, id: \.id)

        #expect(loaded.map(\.name) == ["First", "Second"])
    }

    @Test func `invite text options enforce payload limits`() {
        #expect(CandidateInviteValidation.textIssue(.init(
            fullName: String(repeating: "x", count: 256),
            tags: nil,
            evaluatorEmail: nil,
            emailSubject: nil,
            emailMessage: nil,
            atsCandidateID: nil,
            atsRequisitionID: nil
        ))?.contains("Full name") == true)
        #expect(CandidateInviteValidation.textIssue(.init(
            fullName: nil,
            tags: Array(repeating: "tag", count: 51),
            evaluatorEmail: nil,
            emailSubject: nil,
            emailMessage: nil,
            atsCandidateID: nil,
            atsRequisitionID: nil
        ))?.contains("50 tags") == true)
    }

    @Test func `invite tags preserve first spelling while removing logical duplicates`() {
        #expect(CandidateInviteValidation.normalizedTags(
            " backend, Backend,  BACKEND , iOS, ios, "
        ) == ["backend", "iOS"])
        #expect(CandidateInviteValidation.normalizedTags(" , ") == nil)
    }

    @Test func `optional candidate names are trimmed and omitted when blank`() {
        #expect(CandidateInviteValidation.normalizedFullName("  Ada Lovelace \n") == "Ada Lovelace")
        #expect(CandidateInviteValidation.normalizedFullName(" \n ") == nil)
    }

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

    @Test func `additional time is bounded to one day`() {
        #expect(CandidateInviteValidation.isValid(additionalTime: nil))
        #expect(CandidateInviteValidation.isValid(additionalTime: 0))
        #expect(CandidateInviteValidation.isValid(additionalTime: 1440))
        #expect(!CandidateInviteValidation.isValid(additionalTime: -1))
        #expect(!CandidateInviteValidation.isValid(additionalTime: 1441))
        #expect(!CandidateInviteValidation.isValid(additionalTime: Int.max))
    }

    @Test func `invitation validity window must move forward`() {
        #expect(CandidateInviteValidation.validityOrderIssue(
            validFrom: "2026-08-01T10:00:00Z",
            validUntil: "2026-08-01T11:00:00Z"
        ) == nil)
        #expect(CandidateInviteValidation.validityOrderIssue(
            validFrom: "2026-08-01T10:00:00.500Z",
            validUntil: "2026-08-01T10:00:00.500Z"
        ) != nil)
        #expect(CandidateInviteValidation.validityOrderIssue(
            validFrom: "2026-08-01T10:00:00Z",
            validUntil: "2026-08-01T09:59:59Z"
        ) != nil)
        #expect(CandidateInviteValidation.validityOrderIssue(
            validFrom: "not-yet-validated",
            validUntil: "also-not-yet-validated"
        ) == nil)
    }

    @Test func `invitation validity timestamps must be ISO 8601`() {
        #expect(CandidateInviteValidation.validityTimestampIssue(
            validFrom: "2026-08-01T10:00:00Z",
            validUntil: "2026-08-01T11:00:00.500Z"
        ) == nil)
        #expect(CandidateInviteValidation.validityTimestampIssue(
            validFrom: "tomorrow morning",
            validUntil: nil
        ) == "Valid from must be an ISO-8601 timestamp.")
        #expect(CandidateInviteValidation.validityTimestampIssue(
            validFrom: nil,
            validUntil: "next week"
        ) == "Valid until must be an ISO-8601 timestamp.")
    }
}
