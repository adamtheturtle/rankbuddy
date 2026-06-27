import Foundation

/// Preferences for RankBuddy's built-in MCP server (#75).
///
/// The server is opt-in: an explicit toggle in Settings ▸ MCP enables it, gating both the
/// setup instructions in the UI and the `--mcp` entry point (`RankBuddyEntryPoint`). A client
/// pointed at a disabled server is told to enable it rather than silently serving data.
enum MCPServerSettings {
    /// The `@AppStorage` / `UserDefaults` key for whether the MCP server is enabled.
    static let enabledKey = "rb.mcpServerEnabled"

    /// Whether the MCP server is currently enabled. Defaults to off, so RankBuddy serves the
    /// catalogue only after the user explicitly opts in.
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }
}

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
