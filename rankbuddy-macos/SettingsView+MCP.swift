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

    /// A segmented sub-tab per assistant (Claude Desktop / Claude Code / Codex / Cursor) with the
    /// right config or command to copy, plus where to apply it and how to troubleshoot (#74).
    private var assistantSection: some View {
        Section {
            MCPInstallTabs(command: MCPSetup.command)
        } header: {
            Text("Add to your assistant")
        } footer: {
            Text("The server reads the account currently selected in RankBuddy and never exposes " +
                "your token.")
        }
    }

    /// The tool-call log lives in its own window (mirroring PadBuddy), opened from here.
    private var activitySection: some View {
        Section {
            OpenMCPActivityButton()
        }
    }
}
