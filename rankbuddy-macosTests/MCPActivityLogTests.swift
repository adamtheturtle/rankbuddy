//
//  MCPActivityLogTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the MCP activity log (#52): JSONL parsing and the record→read round-trip.
struct MCPActivityLogTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mcp-\(UUID().uuidString).jsonl")
    }

    @Test func `parsing skips malformed lines`() {
        let jsonl = """
        {"timestamp":"2026-06-27T10:00:00Z","tool":"list_tests","detail":"account: Work"}
        not json
        {"timestamp":"2026-06-27T10:01:00Z","tool":"search_tests","detail":"query: backend"}
        """
        let entries = MCPActivityLog.parse(jsonl)
        #expect(entries.count == 2)
        #expect(entries.first?.tool == "list_tests")
    }

    @Test func `recorded calls read back newest-first`() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        MCPActivityLog.record(tool: "list_tests", detail: "account: Work", to: url)
        MCPActivityLog.record(tool: "search_tests", detail: "query: backend", to: url)

        let entries = MCPActivityLog.entries(from: url)
        #expect(entries.map(\.tool) == ["search_tests", "list_tests"])
    }

    @Test func `clearing removes the log`() {
        let url = tempURL()
        MCPActivityLog.record(tool: "list_tests", detail: "", to: url)
        #expect(!MCPActivityLog.entries(from: url).isEmpty)

        MCPActivityLog.clear(url)
        #expect(MCPActivityLog.entries(from: url).isEmpty)
    }
}
