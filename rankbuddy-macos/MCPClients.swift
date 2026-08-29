//
//  MCPClients.swift
//  rankbuddy-macos
//

import Foundation
import enum MCPClientInstall.MCPDesktopClient
import struct MCPClientInstall.MCPServerSpec

/// The assistants RankBuddy gives MCP setup instructions for (#74). Each carries the config
/// shape its client expects and where its logs live, so the MCP settings pane shows a tab per
/// assistant instead of only the Claude-Desktop JSON. MCPClientInstall supplies the shared
/// `MCPDesktopClient` catalogue; RankBuddy keeps its own troubleshooting copy below.
nonisolated enum MCPClient: String, CaseIterable, Identifiable {
    case claudeDesktop
    case claudeCode
    case codex
    case cursor

    var id: String {
        rawValue
    }

    /// The shared client catalogue entry this maps to for config-snippet generation.
    var buddyClient: MCPDesktopClient {
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
    /// launch `command` (RankBuddy's own executable path). Configuration-file snippets delegate
    /// to MCPClientInstall; Claude Code's documented CLI registration remains a shell command.
    func configText(command: String, serverName: String = "rankbuddy") throws -> String {
        if self == .claudeCode {
            return "claude mcp add \(serverName) -- \"\(command)\" --mcp"
        }
        return try buddyClient.configSnippet(for: server(command: command, name: serverName))
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
    func manualConfigText(command: String, serverName: String = "rankbuddy") throws -> String {
        switch self {
        case .claudeCode:
            try buddyClient.configSnippet(for: server(command: command, name: serverName))
        default:
            try configText(command: command, serverName: serverName)
        }
    }

    private func server(command: String, name: String) -> MCPServerSpec {
        MCPServerSpec(name: name, command: command)
    }
}
