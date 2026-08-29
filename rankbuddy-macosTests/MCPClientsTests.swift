//
//  MCPClientsTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the per-assistant MCP setup text (#74): each client's config format, the
/// ready-to-paste configuration/command it produces, and that the server name is threaded
/// through. Pure string-building, so it's deterministic without any network or store.
///
/// `@MainActor` because `MCPClient.Format`'s synthesised `Equatable` is main-actor-isolated
/// under the app target's default isolation, so the `format == …` comparisons must run there.
@MainActor
struct MCPClientsTests {
    private let command = "/Applications/RankBuddy.app/Contents/MacOS/rankbuddy-macos"

    @Test func `every client has a distinct, non-empty display name`() {
        let names = MCPClient.allCases.map(\.displayName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == MCPClient.allCases.count)
    }

    @Test func `format maps to the client's expected shape`() {
        #expect(MCPClient.claudeDesktop.format == .json)
        #expect(MCPClient.cursor.format == .json)
        #expect(MCPClient.claudeCode.format == .command)
        #expect(MCPClient.codex.format == .toml)
    }

    @Test func `only the CLI client reports isCommand`() {
        #expect(MCPClient.claudeCode.isCommand)
        for client in MCPClient.allCases where client != .claudeCode {
            #expect(!client.isCommand)
        }
    }

    @Test func `the JSON clients emit a launchable mcpServers config`() throws {
        // Decode rather than substring-match: JSONSerialization escapes "/" as "\/", so the raw
        // command path isn't present verbatim — the decoded value is what a client actually reads.
        for client in [MCPClient.claudeDesktop, .cursor] {
            let object = try JSONSerialization.jsonObject(
                with: Data(client.configText(command: command).utf8)
            ) as? [String: Any]
            let entry = (object?["mcpServers"] as? [String: Any])?["rankbuddy"] as? [String: Any]
            #expect(entry?["command"] as? String == command)
            #expect(entry?["args"] as? [String] == ["--mcp"])
        }
    }

    @Test func `the Claude Code client emits an mcp-add command carrying --mcp`() throws {
        let text = try MCPClient.claudeCode.configText(command: command)
        #expect(text.hasPrefix("claude mcp add rankbuddy -- "))
        #expect(text.contains("\"\(command)\""))
        #expect(text.hasSuffix("--mcp"))
    }

    @Test func `the Codex client emits a TOML server block with the launch args`() throws {
        let text = try MCPClient.codex.configText(command: command)
        #expect(text.contains("[mcp_servers.rankbuddy]"))
        #expect(text.contains("command = \"\(command)\""))
        #expect(text.contains("args = [\"--mcp\"]"))
    }

    @Test func `a custom server name is threaded through every format`() throws {
        for client in MCPClient.allCases {
            let text = try client.configText(command: command, serverName: "rb-eu")
            // The custom name reaches the output; the default "rankbuddy" name isn't assumed
            // (and can't be asserted absent, since the command path itself contains it).
            #expect(text.contains("rb-eu"))
        }
    }

    @Test func `every client supplies config-location and troubleshooting hints`() {
        for client in MCPClient.allCases {
            #expect(!client.configLocationHint.isEmpty)
            #expect(!client.troubleshootingHint.isEmpty)
        }
    }
}
