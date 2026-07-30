//
//  MCPActivityLogTests.swift
//  rankbuddy-macosTests
//

import Dispatch
import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the MCP activity log (#52): JSONL parsing and the record→read round-trip.
@MainActor
struct MCPActivityLogTests {
    private func tempURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("activity.jsonl")
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
        #expect(entries[0].id != entries[1].id)
    }

    @Test func `identical calls have unique persisted event identities`() throws {
        let timestamp = "2026-07-30T10:00:00Z"
        let first = MCPActivityLog.boundedEntry(timestamp: timestamp, tool: "list_tests", detail: "")
        let second = MCPActivityLog.boundedEntry(timestamp: timestamp, tool: "list_tests", detail: "")

        #expect(first.id != second.id)
        let restored = try JSONDecoder().decode(
            MCPActivityEntry.self,
            from: JSONEncoder().encode(first)
        )
        #expect(restored.id == first.id)
    }

    @Test func `completed calls preserve outcome duration and account`() throws {
        let entry = MCPActivityLog.boundedEntry(
            timestamp: "2026-07-30T10:00:00Z",
            tool: "create_test",
            detail: "name: Backend",
            outcome: .failed,
            durationMilliseconds: 42,
            account: "Work"
        )
        let restored = try JSONDecoder().decode(
            MCPActivityEntry.self,
            from: JSONEncoder().encode(entry)
        )

        #expect(restored.outcome == .failed)
        #expect(restored.durationMilliseconds == 42)
        #expect(restored.account == "Work")
    }

    @Test func `recorded calls read back newest-first`() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        MCPActivityLog.record(tool: "list_tests", detail: "account: Work", to: url)
        MCPActivityLog.record(tool: "search_tests", detail: "query: backend", to: url)

        let entries = MCPActivityLog.entries(from: url)
        #expect(entries.map(\.tool) == ["search_tests", "list_tests"])
    }

    @Test func `activity entries normalize controls and enforce an encoded byte ceiling`() throws {
        let huge = String(repeating: "👨‍👩‍👧‍👦\n\u{0000}", count: 10000)
        let entry = MCPActivityLog.boundedEntry(
            timestamp: "2026-07-30T10:00:00Z",
            tool: huge,
            detail: huge
        )
        let encoded = try JSONEncoder().encode(entry)

        #expect(encoded.count <= MCPActivityLog.maxEncodedEntryBytes)
        #expect(!entry.tool.contains("\n"))
        #expect(!entry.detail.contains("\n"))
        #expect(!entry.detail.contains("\u{0000}"))
    }

    @Test func `clearing removes the log`() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        MCPActivityLog.record(tool: "list_tests", detail: "", to: url)
        #expect(!MCPActivityLog.entries(from: url).isEmpty)

        MCPActivityLog.clear(url)
        #expect(MCPActivityLog.entries(from: url).isEmpty)
    }

    @Test func `reading trims the physical log to its advertised bound`() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        for index in 0 ..< MCPActivityLog.maxEntries + 5 {
            MCPActivityLog.record(tool: "tool-\(index)", detail: "", to: url)
        }

        #expect(MCPActivityLog.entries(from: url).count == MCPActivityLog.maxEntries)
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.split(separator: "\n").count == MCPActivityLog.maxEntries)
    }

    @Test func `concurrent recorders do not lose entries`() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let count = 100

        DispatchQueue.concurrentPerform(iterations: count) { index in
            MCPActivityLog.record(tool: "tool-\(index)", detail: "detail-\(index)", to: url)
        }

        let entries = MCPActivityLog.entries(from: url)
        #expect(entries.count == count)
        #expect(Set(entries.map(\.tool)).count == count)
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.split(separator: "\n").count == count)
    }
}
