//
//  MCPClientInstallTOMLTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

@MainActor
struct MCPClientInstallTOMLTests {
    @Test func `codex install removes the complete rankbuddy table subtree`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-install-toml-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.toml")
        try """
        [mcp_servers.rankbuddy]
        command = "old"

        [mcp_servers.rankbuddy.env]
        SECRET = "stale"

        [mcp_servers.other]
        command = "other"

        [mcp_servers.rankbuddy.headers]
        authorization = "stale"
        """.write(to: url, atomically: true, encoding: .utf8)

        try MCPClientInstall.upsertCodexServer(
            into: url,
            client: .codex,
            command: "new",
            shouldReplace: { _ in true }
        )

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("[mcp_servers.rankbuddy]\ncommand = \"new\""))
        #expect(text.contains("[mcp_servers.other]\ncommand = \"other\""))
        #expect(!text.contains("rankbuddy.env"))
        #expect(!text.contains("rankbuddy.headers"))
        #expect(!text.contains("stale"))
    }
}
