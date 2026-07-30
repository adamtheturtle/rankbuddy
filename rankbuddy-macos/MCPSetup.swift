//
//  MCPSetup.swift
//  rankbuddy-macos
//

import Foundation

/// Preferences for RankBuddy's built-in MCP server (#75).
///
/// The server is opt-in: an explicit toggle in Settings ▸ MCP enables it, gating both the
/// setup instructions in the UI and the `--mcp` entry point (`RankBuddyEntryPoint`). A client
/// pointed at a disabled server is told to enable it rather than silently serving data.
enum MCPServerSettings {
    /// The `@AppStorage` / `UserDefaults` key for whether the MCP server is enabled.
    static let enabledKey = "rb.mcpServerEnabled"

    /// The `@AppStorage` / `UserDefaults` key for whether the MCP server may make changes —
    /// a separate, explicit opt-in from `enabledKey` so read tools work without ever exposing
    /// writes by accident (#73).
    static let allowWritesKey = "rb.mcpServerAllowWrites"

    /// Whether the MCP server is currently enabled. Defaults to off, so RankBuddy serves the
    /// catalogue only after the user explicitly opts in.
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    /// Whether the MCP server may advertise and run write tools (create/update/delete). Defaults
    /// to off: even with the server enabled, writes stay hidden until this is explicitly turned
    /// on, and it only takes effect after the assistant restarts the server process (#73).
    static func allowsWrites(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: allowWritesKey)
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
    static var command: String? {
        resolvedCommand(executablePath: Bundle.main.executablePath)
    }

    static func resolvedCommand(executablePath: String?) -> String? {
        guard let executablePath else { return nil }

        let trimmed = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A ready-to-paste MCP-client configuration (the `mcpServers` shape used by clients such
    /// as Claude Desktop), pretty-printed.
    static func clientConfigJSON(command: String?, serverName: String = "rankbuddy") -> String? {
        guard let command = resolvedCommand(executablePath: command) else { return nil }

        let config: [String: Any] = [
            "mcpServers": [
                serverName: ["command": command, "args": ["--mcp"]]
            ]
        ]
        let data = (try? JSONSerialization.data(
            withJSONObject: config, options: [.prettyPrinted, .sortedKeys]
        )) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8)
    }
}
