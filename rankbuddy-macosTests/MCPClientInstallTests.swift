//
//  MCPClientInstallTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

@MainActor
struct MCPClientInstallTests {
    @Test func `JSON install preserves existing servers and adds rankbuddy`() throws {
        let url = try temporaryFile(named: "mcp.json")
        try "{\"mcpServers\":{\"other\":{\"command\":\"other\",\"args\":[]}}}".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )

        try MCPClientInstall.mergeJSONServer(
            into: url,
            client: .cursor,
            command: "/Applications/RankBuddy.app/Contents/MacOS/rankbuddy-macos",
            shouldReplace: { _ in true }
        )

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let servers = try #require(object?["mcpServers"] as? [String: Any])
        let other = try #require(servers["other"] as? [String: Any])
        let rankbuddy = try #require(servers["rankbuddy"] as? [String: Any])

        #expect(other["command"] as? String == "other")
        #expect(rankbuddy["command"] as? String == "/Applications/RankBuddy.app/Contents/MacOS/rankbuddy-macos")
        #expect(rankbuddy["args"] as? [String] == ["--mcp"])
    }

    @Test func `JSON install leaves existing rankbuddy entry untouched when update is cancelled`() throws {
        let url = try temporaryFile(named: "mcp.json")
        try "{\"mcpServers\":{\"rankbuddy\":{\"command\":\"old\",\"args\":[\"--mcp\"]}}}".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )

        try MCPClientInstall.mergeJSONServer(
            into: url,
            client: .claudeDesktop,
            command: "new",
            shouldReplace: { _ in false }
        )

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let servers = try #require(object?["mcpServers"] as? [String: Any])
        let rankbuddy = try #require(servers["rankbuddy"] as? [String: Any])
        #expect(rankbuddy["command"] as? String == "old")
    }

    @Test func `Codex install replaces only rankbuddy table`() throws {
        let url = try temporaryFile(named: "config.toml")
        try """
        [mcp_servers.other]
        command = "other"
        args = []

        [mcp_servers.rankbuddy]
        command = "old"
        args = ["--mcp"]

        [tools]
        enabled = true
        """.write(to: url, atomically: true, encoding: .utf8)

        try MCPClientInstall.upsertCodexServer(
            into: url,
            client: .codex,
            command: "new",
            shouldReplace: { _ in true }
        )

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("[mcp_servers.other]\ncommand = \"other\""))
        #expect(text.contains("[mcp_servers.rankbuddy]\ncommand = \"new\"\nargs = [\"--mcp\"]"))
        #expect(!text.contains("command = \"old\""))
        #expect(text.contains("[tools]\nenabled = true"))
    }

    private func temporaryFile(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }
}
