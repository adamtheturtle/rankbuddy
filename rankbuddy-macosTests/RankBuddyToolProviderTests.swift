//
//  RankBuddyToolProviderTests.swift
//  rankbuddy-macosTests
//

import BuddyAppKit
import Foundation
import MCP
import MCPKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the RankBuddy MCP tool catalogue (#9). Uses a seeded **demo** account so the
/// tools dispatch through the in-process mock — no live credentials, deterministic results.
@MainActor
struct RankBuddyToolProviderTests {
    private func provider() -> RankBuddyToolProvider {
        RankBuddyToolProvider(makeStore: {
            AccountStore.rankBuddy(isTesting: true, seed: [Account(label: "Demo", token: Account.demoToken)])
        })
    }

    /// A provider with the write opt-in on (#73), backed by the same seeded demo/mock store.
    private func writeProvider() -> RankBuddyToolProvider {
        RankBuddyToolProvider(allowWrites: true, makeStore: {
            AccountStore.rankBuddy(isTesting: true, seed: [Account(label: "Demo", token: Account.demoToken)])
        })
    }

    /// The first text block of a tool result.
    private func text(_ result: CallTool.Result) -> String {
        for content in result.content {
            if case let .text(value, _, _) = content { return value }
        }
        return ""
    }

    @Test func `tools advertise the read-only catalogue`() async {
        let names = await provider().tools().map(\.name)
        #expect(names.contains("list_accounts"))
        #expect(names.contains("list_tests"))
        #expect(names.contains("list_questions"))
        #expect(names.contains("list_interviews"))
        #expect(names.contains("list_candidates"))
        #expect(names.contains("list_users"))
        #expect(names.contains("list_teams"))
        // Every tool is flagged read-only.
        let tools = await provider().tools()
        #expect(tools.allSatisfy { $0.annotations.readOnlyHint == true })
    }

    @Test func `list_users returns the organisation's members`() async {
        let result = await provider().callTool("list_users", arguments: nil)
        let body = text(result)
        #expect(result.isError != true)
        #expect(body.contains("\"users\""))
        #expect(body.contains("rhea@example.com"))
        #expect(!body.contains("\"count\" : 0"))
    }

    @Test func `list_teams returns teams with member counts`() async {
        let result = await provider().callTool("list_teams", arguments: nil)
        let body = text(result)
        #expect(result.isError != true)
        #expect(body.contains("\"teams\""))
        #expect(body.contains("Backend Hiring"))
        #expect(body.contains("\"developers\""))
    }

    @Test func `list_accounts names the account without exposing a token`() async {
        let result = await provider().callTool("list_accounts", arguments: nil)
        let body = text(result)
        #expect(result.isError != true)
        #expect(body.contains("Demo"))
        #expect(!body.lowercased().contains("token"))
    }

    @Test func `list_tests returns the mock account's tests`() async {
        let result = await provider().callTool("list_tests", arguments: nil)
        let body = text(result)
        #expect(result.isError != true)
        #expect(body.contains("\"tests\""))
        #expect(body.contains("\"account\" : \"Demo\""))
        // The mock tests fixture is non-empty.
        #expect(!body.contains("\"count\" : 0"))
    }

    @Test func `list_candidates requires a test_id`() async {
        let result = await provider().callTool("list_candidates", arguments: nil)
        #expect(result.isError == true)
        #expect(text(result).contains("test_id"))
    }

    @Test func `list_candidates returns a test's candidates`() async {
        let result = await provider().callTool("list_candidates", arguments: ["test_id": .string("t1")])
        #expect(result.isError != true)
        #expect(text(result).contains("\"candidates\""))
    }

    @Test func `an unknown tool is an error`() async {
        let result = await provider().callTool("delete_everything", arguments: nil)
        #expect(result.isError == true)
        #expect(text(result).contains("Unknown tool"))
    }

    // MARK: - Search

    @Test func `search_tests finds a matching test`() async {
        let result = await provider().callTool("search_tests", arguments: ["query": .string("Backend")])
        let body = text(result)
        #expect(result.isError != true)
        #expect(body.contains("Backend"))
        #expect(!body.contains("\"count\" : 0"))
    }

    @Test func `search_tests returns no matches for an absent term`() async {
        let result = await provider().callTool("search_tests", arguments: ["query": .string("zzz-nope-zzz")])
        let body = text(result)
        #expect(result.isError != true)
        #expect(body.contains("\"count\" : 0"))
        // It still scanned the (non-empty) collection.
        #expect(!body.contains("\"scanned\" : 0"))
    }

    @Test func `search requires a query`() async {
        let result = await provider().callTool("search_tests", arguments: nil)
        #expect(result.isError == true)
        #expect(text(result).contains("query"))
    }

    // MARK: - Server-side people/candidate search (#104)

    @Test func `the catalogue advertises the server-side search tools`() async {
        let names = await provider().tools().map(\.name)
        #expect(names.contains("search_users"))
        #expect(names.contains("search_candidates"))
    }

    @Test func `search_users matches a user server-side`() async {
        let result = await provider().callTool("search_users", arguments: ["query": .string("rhea")])
        let body = text(result)
        #expect(result.isError != true)
        #expect(body.contains("rhea@example.com"))
        #expect(body.contains("\"matches\""))
        #expect(!body.contains("\"count\" : 0"))
    }

    @Test func `search_users requires a query`() async {
        let result = await provider().callTool("search_users", arguments: nil)
        #expect(result.isError == true)
        #expect(text(result).contains("query"))
    }

    @Test func `search_candidates matches a candidate in a test`() async {
        let result = await provider().callTool(
            "search_candidates", arguments: ["test_id": .string("t1"), "query": .string("ada")]
        )
        let body = text(result)
        #expect(result.isError != true)
        #expect(body.contains("Ada Lovelace"))
        #expect(body.contains("\"test_id\" : \"t1\""))
    }

    @Test func `search_candidates requires a test_id`() async {
        let result = await provider().callTool("search_candidates", arguments: ["query": .string("ada")])
        #expect(result.isError == true)
        #expect(text(result).contains("test_id"))
    }

    // MARK: - Resources & prompts

    @Test func `the accounts resource is advertised and readable`() async throws {
        let resources = await provider().resources()
        #expect(resources.contains { $0.uri == RankBuddyToolProvider.accountsURI })

        let read = try await provider().readResource(RankBuddyToolProvider.accountsURI)
        let joined = read.contents.compactMap(\.text).joined()
        #expect(joined.contains("Demo"))
        #expect(!joined.lowercased().contains("token"))
    }

    @Test func `an unknown resource throws`() async {
        await #expect(throws: (any Error).self) {
            _ = try await provider().readResource("rankbuddy://nope")
        }
    }

    @Test func `the triage prompt is advertised and renders with a test id`() async throws {
        let prompts = await provider().prompts()
        #expect(prompts.contains { $0.name == "triage_candidates" })

        let rendered = try await provider().getPrompt("triage_candidates", arguments: ["test_id": "t1"])
        #expect(!rendered.messages.isEmpty)
    }

    @Test func `the triage prompt requires a test id`() async {
        await #expect(throws: (any Error).self) {
            _ = try await provider().getPrompt("triage_candidates", arguments: nil)
        }
    }

    @Test func `an unknown prompt throws`() async {
        await #expect(throws: (any Error).self) {
            _ = try await provider().getPrompt("nope", arguments: nil)
        }
    }

    // MARK: - Write tools (#73)

    @Test func `write tools are hidden while writes are off`() async {
        let names = await provider().tools().map(\.name)
        #expect(!names.contains("create_test"))
        #expect(!names.contains("delete_test"))
        // Read tools are still there.
        #expect(names.contains("list_tests"))
    }

    @Test func `a write tool is refused while writes are off`() async {
        let result = await provider().callTool("create_test", arguments: ["name": .string("Backend")])
        #expect(result.isError == true)
        #expect(text(result).contains("Allow the MCP server to make changes"))
    }

    @Test func `write tools are advertised when writes are on`() async {
        let tools = await writeProvider().tools()
        let names = tools.map(\.name)
        #expect(names.contains("create_test"))
        #expect(names.contains("delete_test"))
        #expect(names.contains("invite_candidate"))
        #expect(names.contains("schedule_interview"))
        // The write tools are flagged not-read-only.
        let writeTools = tools.filter { RankBuddyToolProvider.isWriteTool($0.name) }
        #expect(writeTools.allSatisfy { $0.annotations.readOnlyHint == false })
    }

    @Test func `create_test runs against the mock when writes are on`() async {
        let result = await writeProvider().callTool("create_test", arguments: ["name": .string("Backend Screen")])
        let body = text(result)
        #expect(result.isError != true)
        #expect(body.contains("created_test"))
        #expect(body.contains("t-created"))
    }

    @Test func `create_test requires a name`() async {
        let result = await writeProvider().callTool("create_test", arguments: nil)
        #expect(result.isError == true)
        #expect(text(result).contains("name"))
    }

    @Test func `invite_candidate accepts richer invite options`() async {
        let result = await writeProvider().callTool(
            "invite_candidate",
            arguments: [
                "test_id": .string("t1"),
                "email": .string("new@example.com"),
                "additional_time": .int(15),
                "tags": .array([.string("onsite"), .string("backend")]),
                "email_subject": .string("Backend screen"),
                "email_message": .string("Please complete this screen."),
                "evaluator_email": .string("reviewer@example.com"),
                "ats_candidate_id": .string("cand-123"),
                "ats_requisition_id": .string("req-456")
            ]
        )
        let body = text(result)
        #expect(result.isError != true)
        #expect(body.contains("invited_candidate"))
        #expect(body.contains("new@example.com"))
    }

    @Test func `invite_candidate rejects negative additional time`() async {
        let result = await writeProvider().callTool(
            "invite_candidate",
            arguments: [
                "test_id": .string("t1"),
                "email": .string("new@example.com"),
                "additional_time": .int(-1)
            ]
        )
        #expect(result.isError == true)
        #expect(text(result).contains("additional_time"))
    }

    @Test func `schedule_interview rejects a non-ISO-8601 start time`() async {
        let result = await writeProvider().callTool(
            "schedule_interview", arguments: ["title": .string("Pairing"), "from": .string("next tuesday")]
        )
        #expect(result.isError == true)
        #expect(text(result).contains("ISO-8601"))
    }
}
