//
//  MCPClients.swift
//  rankbuddy-macos
//

import Foundation
import MCPKit

/// The assistants RankBuddy gives MCP setup instructions for (#74). Each carries the config
/// shape its client expects and where its logs live, so the MCP settings pane shows a tab per
/// assistant instead of only the Claude-Desktop JSON. The shared snippet builder is buddy-kit's
/// `MCPKit.MCPClient` (#647); RankBuddy keeps its own location/troubleshooting copy below.
enum MCPClient: String, CaseIterable, Identifiable {
    case claudeDesktop
    case claudeCode
    case codex
    case cursor

    var id: String {
        rawValue
    }

    /// The buddy-kit client this maps to, for the shared display name and config-snippet builder.
    var buddyClient: MCPKit.MCPClient {
        switch self {
        case .claudeDesktop: .claudeDesktop
        case .claudeCode: .claudeCode
        case .codex: .codex
        case .cursor: .cursor
        }
    }

    var displayName: String {
        switch self {
        case .claudeDesktop: "Claude Desktop"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    /// How the client is configured, which decides whether we show a JSON block, a CLI
    /// command, or a TOML snippet.
    enum Format {
        case json
        case command
        case toml
    }

    var format: Format {
        switch self {
        case .claudeDesktop, .cursor: .json
        case .claudeCode: .command
        case .codex: .toml
        }
    }

    /// Whether the shown text is a shell command (vs a config block) — changes the copy label.
    var isCommand: Bool {
        format == .command
    }

    /// The ready-to-use configuration (or command) for this client, for the given server
    /// launch `command` (RankBuddy's own executable path). Delegates to buddy-kit's shared
    /// `configSnippet` (#647) so the JSON/command/TOML builders live in one place.
    func configText(command: String, serverName: String = "rankbuddy") -> String {
        buddyClient.configSnippet(command: command, serverName: serverName)
    }

    /// Where this client keeps its config (or how to apply it), shown as a hint. The path may
    /// not exist yet.
    var configLocationHint: String {
        switch self {
        case .claudeDesktop:
            "Paste into ~/Library/Application Support/Claude/claude_desktop_config.json, then restart Claude Desktop."
        case .claudeCode:
            "Run the command in your terminal, or add it to a project .mcp.json."
        case .codex:
            "Paste into ~/.codex/config.toml, then restart Codex."
        case .cursor:
            "Paste into ~/.cursor/mcp.json (global) or .cursor/mcp.json in a project, then reload Cursor."
        }
    }

    /// A short "if it doesn't show up, check here" troubleshooting hint.
    var troubleshootingHint: String {
        switch self {
        case .claudeDesktop: "If it doesn't appear, check ~/Library/Logs/Claude/mcp*.log."
        case .claudeCode: "Run `claude mcp list` to confirm it registered."
        case .codex: "If it doesn't appear, check ~/.codex/log/ after restarting."
        case .cursor: "MCP output appears in Cursor's Output panel (MCP Logs)."
        }
    }
}
