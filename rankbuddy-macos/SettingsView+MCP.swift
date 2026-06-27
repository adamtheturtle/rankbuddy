//
//  SettingsView+MCP.swift
//  rankbuddy-macos
//

import BuddyAppKit
import SwiftUI

/// The MCP setup + activity sections, split out so `SettingsView.swift` stays under the
/// file-length limit. Shown only once the server is enabled (#75).
extension SettingsView {
    var mcpConfigSections: some View {
        Group {
            assistantSection
            activitySection
        }
    }

    /// A tab per assistant (Claude Desktop / Claude Code / Codex / Cursor) with the right
    /// config or command to copy, plus where to apply it and how to troubleshoot (#74).
    private var assistantSection: some View {
        Section {
            Picker("Assistant", selection: $mcpClient) {
                ForEach(MCPClient.allCases) { client in
                    Text(client.displayName).tag(client)
                }
            }

            Text(mcpClient.configText(command: MCPSetup.command))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Clipboard.copy(mcpClient.configText(command: MCPSetup.command))
            } label: {
                Label(mcpClient.isCommand ? "Copy Command" : "Copy Configuration", systemImage: "doc.on.doc")
            }
        } header: {
            Text("Add to your assistant")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(mcpClient.configLocationHint)
                Text(mcpClient.troubleshootingHint)
                Text("The server reads the account currently selected in RankBuddy and never exposes your token.")
            }
        }
    }

    private var activitySection: some View {
        Section {
            if mcpActivity.isEmpty {
                Text("No MCP activity recorded yet.").foregroundStyle(.secondary)
            } else {
                ForEach(mcpActivity) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.tool).font(.callout.monospaced())
                        Text([DisplayFormat.date(entry.timestamp) ?? entry.timestamp, entry.detail]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("Activity")
                Spacer()
                Button("Refresh") { mcpActivity = MCPActivityLog.entries() }
                if !mcpActivity.isEmpty {
                    Button("Clear") { MCPActivityLog.clear(); mcpActivity = [] }
                }
            }
        } footer: {
            Text("Recent tool calls served by the MCP server. It runs as a separate process, " +
                "so this updates when you Refresh.")
        }
    }
}
