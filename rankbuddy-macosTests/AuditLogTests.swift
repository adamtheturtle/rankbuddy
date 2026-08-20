//
//  AuditLogTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the account activity feed (#106): the `AuditLogEntry` model's resilient decoding
/// and the client method that pages the audit log through the demo server.
@MainActor
struct AuditLogTests {
    private func makeClient() -> HackerRankClient {
        HackerRankClient(account: Account(label: "Demo", token: Account.demoToken))
    }

    // MARK: - Client routing

    @Test func `audit log page decodes through the client`() async throws {
        let page = try await makeClient().auditLogPage()
        #expect(page.items.count == 3)
        #expect(page.next == nil)
        #expect(page.items.first?.sourceType == "test")
        #expect(page.items.first?.action == "update")
    }

    // MARK: - Resilient decoding

    @Test func `source id decodes from both a string and a number`() async throws {
        let page = try await makeClient().auditLogPage()
        // The third fixture entry carries a numeric source_id (1024); it must surface as a string.
        #expect(page.items.contains { $0.sourceID == "1024" })
        #expect(page.items.contains { $0.sourceID == "t1" })
    }

    @Test func `user decodes from both an object and a bare string`() async throws {
        let page = try await makeClient().auditLogPage()
        // Object form → "First Last"; bare-string (email) form → the email verbatim.
        #expect(page.items.contains { $0.userLabel == "Rhea Recruiter" })
        #expect(page.items.contains { $0.userLabel == "ian@example.com" })
    }

    @Test func `entry tolerates a sparse record`() throws {
        let entry = try JSONDecoder().decode(AuditLogEntry.self, from: Data("{}".utf8))
        #expect(entry.sourceID == nil)
        #expect(entry.modifiedFields.isEmpty)
        #expect(entry.userLabel == nil)
    }

    @Test func `paged entries reconcile duplicate stable IDs in server order`() throws {
        let first = try JSONDecoder().decode(
            AuditLogEntry.self,
            from: Data(
                """
                {"source_id":"t1","source_type":"test","action":"update",
                 "created_at":"2026-07-01","modified_fields":["name"]}
                """.utf8
            )
        )
        let repeated = try JSONDecoder().decode(
            AuditLogEntry.self,
            from: Data(
                """
                {"source_id":"t1","source_type":"test","action":"update",
                 "created_at":"2026-07-01","modified_fields":["cutoff_score"]}
                """.utf8
            )
        )
        let later = try JSONDecoder().decode(
            AuditLogEntry.self,
            from: Data(
                #"{"source_id":"q2","source_type":"question","action":"create","created_at":"2026-06-30"}"#.utf8
            )
        )

        let merged = AccountActivityView.mergedEntries([first], with: [repeated, later, later])

        #expect(merged.map(\.id) == [first.id, repeated.id, later.id])
        #expect(merged.contains { $0.modifiedFields == ["cutoff_score"] })
    }

    @Test func `only the current account reload generation may publish`() {
        let firstAccount = UUID()
        let secondAccount = UUID()

        #expect(
            AccountActivityView.isCurrentRequest(
                accountID: secondAccount,
                currentAccountID: secondAccount,
                generation: 2,
                currentGeneration: 2
            )
        )
        #expect(
            !AccountActivityView.isCurrentRequest(
                accountID: firstAccount,
                currentAccountID: secondAccount,
                generation: 1,
                currentGeneration: 2
            )
        )
        #expect(
            !AccountActivityView.isCurrentRequest(
                accountID: secondAccount,
                currentAccountID: secondAccount,
                generation: 1,
                currentGeneration: 2
            )
        )
    }

    @Test func `pagination must match its account generation and cursor`() {
        let accountID = UUID()

        #expect(
            AccountActivityView.isCurrentPagination(
                .init(accountID: accountID, generation: 3, cursor: "page-2"),
                currentAccountID: accountID,
                currentGeneration: 3,
                currentCursor: "page-2"
            )
        )
        #expect(
            !AccountActivityView.isCurrentPagination(
                .init(accountID: accountID, generation: 3, cursor: "page-2"),
                currentAccountID: UUID(),
                currentGeneration: 3,
                currentCursor: "page-2"
            )
        )
        #expect(
            !AccountActivityView.isCurrentPagination(
                .init(accountID: accountID, generation: 3, cursor: "page-2"),
                currentAccountID: accountID,
                currentGeneration: 4,
                currentCursor: "new-page-2"
            )
        )
    }

    @Test func `pagination detects direct and multi-page cursor cycles`() {
        #expect(AccountActivityView.hasCursorCycle(next: "c1", requested: "c1", previouslyLoaded: []))
        #expect(AccountActivityView.hasCursorCycle(next: "c1", requested: "c2", previouslyLoaded: ["c1"]))
        #expect(!AccountActivityView.hasCursorCycle(next: "c3", requested: "c2", previouslyLoaded: ["c1"]))
    }

    // MARK: - Display helpers

    @Test func `headline summarises the action, type, and id`() throws {
        let json = #"{"source_id":"t1","source_type":"test","action":"update"}"#
        let entry = try JSONDecoder().decode(AuditLogEntry.self, from: Data(json.utf8))
        #expect(entry.headline == "Update test t1")
        #expect(entry.actionSymbol == "pencil")
    }

    @Test func `headline falls back when fields are missing`() throws {
        let entry = try JSONDecoder().decode(AuditLogEntry.self, from: Data("{}".utf8))
        #expect(entry.headline == "Changed record")
        #expect(entry.actionSymbol == "circle")
    }
}
