import Foundation

/// Helpers for configuring an external MCP client to use RankBuddy's `--mcp` server (#9).
///
/// RankBuddy serves its read-only catalogue when its own binary is launched with `--mcp`
/// (see `RankBuddyEntryPoint`). An MCP client (Claude Desktop, etc.) is pointed at that
/// command; this builds the ready-to-paste configuration shown in Settings.
enum MCPSetup {
    /// The command an MCP client runs to launch RankBuddy as a stdio server — the app's own
    /// executable path.
    static var command: String {
        Bundle.main.executablePath ?? ""
    }

    /// A ready-to-paste MCP-client configuration (the `mcpServers` shape used by clients such
    /// as Claude Desktop), pretty-printed.
    static func clientConfigJSON(command: String = Self.command, serverName: String = "rankbuddy") -> String {
        let config: [String: Any] = [
            "mcpServers": [
                serverName: ["command": command, "args": ["--mcp"]]
            ]
        ]
        let data = (try? JSONSerialization.data(
            withJSONObject: config, options: [.prettyPrinted, .sortedKeys]
        )) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
