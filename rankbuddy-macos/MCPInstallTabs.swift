//
//  MCPInstallTabs.swift
//  rankbuddy-macos
//
//  Per-client MCP setup as segmented sub-tabs in the MCP settings pane: pick the assistant,
//  add RankBuddy to it automatically, or expand the manual fallback to copy the exact snippet.
//

import BuddyAppKit
import SwiftUI

struct MCPInstallTabs: View {
    /// The command an MCP client runs to launch RankBuddy as a stdio server (its own executable).
    let command: String?
    @State private var client: MCPClient = .claudeDesktop
    @State private var installRevision = 0

    private var needsRepair: Bool {
        _ = installRevision
        guard let command else { return false }

        return MCPClientInstall.needsRepair(client, currentCommand: command)
    }

    var body: some View {
        Picker("Assistant", selection: $client) {
            ForEach(MCPClient.allCases) { option in
                Text(option.displayName).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        if command == nil {
            Label(
                "RankBuddy can’t locate its executable, so assistant configuration is unavailable.",
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.red)
        } else {
            Text("Adds RankBuddy to \(client.displayName). \(client.restartHint)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        if needsRepair {
            Label(
                "RankBuddy has moved since this configuration was installed. " +
                    "Repair it before restarting the assistant.",
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.orange)
        }

        Button {
            guard let command else { return }

            MCPClientInstall.install(client, command: command) {
                installRevision += 1
            }
        } label: {
            Label(
                "\(needsRepair ? "Repair" : "Add to") \(client.displayName)",
                systemImage: needsRepair ? "wrench.and.screwdriver" : "wand.and.stars"
            )
        }
        .disabled(command == nil)

        Text(LocalizedStringKey(client.troubleshootingHint))
            .font(.callout)
            .foregroundStyle(.secondary)

        DisclosureGroup("Prefer to edit the file yourself?") {
            manualInstructions
        }
        .font(.callout)
    }

    @ViewBuilder
    private var manualInstructions: some View {
        if let command {
            let snippet = client.manualConfigText(command: command)
            Text("Add the `rankbuddy` server to this file. Create it with the text below if it doesn't exist, " +
                "otherwise add just the `rankbuddy` block to what's already there:")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(client.configPath)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(snippet)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )

            Button {
                Clipboard.copy(snippet)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        } else {
            Text("Manual configuration is unavailable because no executable command can be generated.")
                .foregroundStyle(.secondary)
        }
    }
}
