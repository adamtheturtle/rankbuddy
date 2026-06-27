import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the MCP client-configuration helper shown in Settings (#9).
struct MCPSetupTests {
    @Test func `the config is valid JSON with the server's launch command`() throws {
        let json = MCPSetup.clientConfigJSON(command: "/path/to/RankBuddy", serverName: "rankbuddy")
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let servers = try #require(object?["mcpServers"] as? [String: Any])
        let server = try #require(servers["rankbuddy"] as? [String: Any])
        #expect(server["command"] as? String == "/path/to/RankBuddy")
        #expect(server["args"] as? [String] == ["--mcp"])
    }

    @Test func `the server name is configurable`() throws {
        let json = MCPSetup.clientConfigJSON(command: "/x", serverName: "hr")
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let servers = try #require(object?["mcpServers"] as? [String: Any])
        #expect(servers["hr"] != nil)
        #expect(servers["rankbuddy"] == nil)
    }

    @Test func `the MCP server is opt-in: disabled by default, on once the key is set`() throws {
        let defaults = try #require(UserDefaults(suiteName: "mcp-server-settings-test"))
        defaults.removePersistentDomain(forName: "mcp-server-settings-test")

        #expect(MCPServerSettings.isEnabled(defaults: defaults) == false)

        defaults.set(true, forKey: MCPServerSettings.enabledKey)
        #expect(MCPServerSettings.isEnabled(defaults: defaults) == true)

        defaults.removePersistentDomain(forName: "mcp-server-settings-test")
    }
}
