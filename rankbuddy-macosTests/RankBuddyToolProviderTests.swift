import BuddyAppKit
import BuddyMCP
import Foundation
import MCP
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
        // Every tool is flagged read-only.
        let tools = await provider().tools()
        #expect(tools.allSatisfy { $0.annotations.readOnlyHint == true })
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
}
