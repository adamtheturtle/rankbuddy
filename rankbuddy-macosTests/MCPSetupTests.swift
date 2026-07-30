//
//  MCPSetupTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the MCP client-configuration helper shown in Settings (#9).
@MainActor
struct MCPSetupTests {
    @Test func `the config is valid JSON with the server's launch command`() throws {
        let json = try #require(MCPSetup.clientConfigJSON(
            command: "/path/to/RankBuddy",
            serverName: "rankbuddy"
        ))
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let servers = try #require(object?["mcpServers"] as? [String: Any])
        let server = try #require(servers["rankbuddy"] as? [String: Any])
        #expect(server["command"] as? String == "/path/to/RankBuddy")
        #expect(server["args"] as? [String] == ["--mcp"])
    }

    @Test func `the server name is configurable`() throws {
        let json = try #require(MCPSetup.clientConfigJSON(command: "/x", serverName: "hr"))
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let servers = try #require(object?["mcpServers"] as? [String: Any])
        #expect(servers["hr"] != nil)
        #expect(servers["rankbuddy"] == nil)
    }

    @Test func `missing or blank executable paths cannot generate configuration`() {
        #expect(MCPSetup.resolvedCommand(executablePath: nil) == nil)
        #expect(MCPSetup.resolvedCommand(executablePath: " \n ") == nil)
        #expect(MCPSetup.clientConfigJSON(command: nil) == nil)
        #expect(MCPSetup.clientConfigJSON(command: "") == nil)
    }

    @Test func `the MCP server is opt-in: disabled by default, on once the key is set`() throws {
        let defaults = try #require(UserDefaults(suiteName: "mcp-server-settings-test"))
        defaults.removePersistentDomain(forName: "mcp-server-settings-test")

        #expect(MCPServerSettings.isEnabled(defaults: defaults) == false)

        defaults.set(true, forKey: MCPServerSettings.enabledKey)
        #expect(MCPServerSettings.isEnabled(defaults: defaults) == true)

        defaults.removePersistentDomain(forName: "mcp-server-settings-test")
    }

    @Test func `disabling the MCP server revokes write authorization`() {
        #expect(MCPServerSettings.writeAuthorization(serverEnabled: false, currentlyAllowed: true) == false)
        #expect(MCPServerSettings.writeAuthorization(serverEnabled: true, currentlyAllowed: false) == false)
        #expect(MCPServerSettings.writeAuthorization(serverEnabled: true, currentlyAllowed: true))
    }

    @Test func `the JSON clients emit a valid mcpServers block with the launch command`() throws {
        for client in [MCPClient.claudeDesktop, .cursor] {
            #expect(client.isCommand == false)
            let text = client.configText(command: "/path/to/RankBuddy")
            let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
            let servers = try #require(object?["mcpServers"] as? [String: Any])
            let server = try #require(servers["rankbuddy"] as? [String: Any])
            #expect(server["command"] as? String == "/path/to/RankBuddy")
            #expect(server["args"] as? [String] == ["--mcp"])
        }
    }

    @Test func `the CLI client shows a Claude Code add command and Codex shows a TOML table`() {
        let claudeCode = MCPClient.claudeCode.configText(command: "/path/to/RankBuddy")
        #expect(MCPClient.claudeCode.isCommand)
        #expect(claudeCode.hasPrefix("claude mcp add rankbuddy -- "))
        #expect(claudeCode.contains("/path/to/RankBuddy"))
        #expect(claudeCode.hasSuffix("--mcp"))

        let codex = MCPClient.codex.configText(command: "/path/to/RankBuddy")
        #expect(codex.contains("[mcp_servers.rankbuddy]"))
        #expect(codex.contains("command = \"/path/to/RankBuddy\""))
        #expect(codex.contains("args = [\"--mcp\"]"))
    }
}
