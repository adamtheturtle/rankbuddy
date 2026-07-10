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

    /// The config file the one-click installer updates, also shown in the manual fallback.
    var configPath: String {
        switch self {
        case .claudeDesktop: "~/Library/Application Support/Claude/claude_desktop_config.json"
        case .claudeCode: "~/.claude.json"
        case .codex: "~/.codex/config.toml"
        case .cursor: "~/.cursor/mcp.json"
        }
    }

    /// Where this client keeps its config, shown as a setup hint. The path may not exist yet.
    var configLocationHint: String {
        "Adds or updates the `rankbuddy` server in \(configPath)."
    }

    /// How the client picks up a newly installed server entry.
    var restartHint: String {
        switch self {
        case .claudeDesktop: "Quit Claude Desktop with Command-Q and reopen it, then ask it about your HackerRank data."
        case .claudeCode: "Start a fresh Claude Code session or run /mcp, then ask it about your HackerRank data."
        case .codex: "Restart Codex, then ask it about your HackerRank data."
        case .cursor: "Reload Cursor or toggle the server in MCP settings, then ask it about your HackerRank data."
        }
    }

    /// A short "if it doesn't show up, check here" troubleshooting hint.
    var troubleshootingHint: String {
        switch self {
        case .claudeDesktop: "If it doesn't appear, check ~/Library/Logs/Claude/mcp*.log."
        case .claudeCode: "Confirm it connected with `claude mcp list` or `claude mcp get rankbuddy`."
        case .codex: "If it doesn't appear, check ~/.codex/log/ after restarting."
        case .cursor: "MCP output appears in Cursor's Output panel (MCP Logs)."
        }
    }

    /// The snippet to paste into the config file by hand. Claude Code's install path is its
    /// JSON config file, so the manual fallback shows JSON rather than the CLI command.
    func manualConfigText(command: String, serverName: String = "rankbuddy") -> String {
        switch self {
        case .claudeCode:
            MCPKit.MCPClient.claudeDesktop.configSnippet(command: command, serverName: serverName)
        default:
            configText(command: command, serverName: serverName)
        }
    }
}
