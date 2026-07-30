//
//  MCPActivityWindow.swift
//  rankbuddy-macos
//
//  The MCP tool-call activity log as its own window, opened from the MCP settings pane rather than
//  an inline section (mirroring PadBuddy). Shows the recent tool calls the headless `--mcp` server
//  has served, read from `MCPActivityLog` (a shared file in the app container).
//

import BuddyAppKit
import SwiftUI

struct MCPActivityView: View {
    @State private var activity: [MCPActivityEntry] = []
    @State private var clearPresented = false

    var body: some View {
        Group {
            if activity.isEmpty {
                ContentUnavailableView(
                    "No MCP activity yet",
                    systemImage: "bolt.horizontal.circle",
                    description: Text("Connect an assistant to the server and its tool calls show up here.")
                )
            } else {
                Form {
                    Section {
                        ForEach(activity) { entry in
                            callRow(entry)
                        }
                    } header: {
                        Text("Recent tool calls")
                    } footer: {
                        Text("Recorded on this Mac — tool names, times, and a short detail only, never " +
                            "candidate or test content. The server runs as a separate process, so this " +
                            "updates when you Refresh.")
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(minWidth: 440, minHeight: 360)
        .onAppear { reload() }
        .toolbar {
            Button {
                reload()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) {
                clearPresented = true
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(activity.isEmpty)
        }
        .confirmationDialog(
            "Clear MCP activity?",
            isPresented: $clearPresented,
            titleVisibility: .visible
        ) {
            Button("Clear Activity", role: .destructive) {
                MCPActivityLog.clear()
                activity = []
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the MCP audit history on this Mac. This can’t be undone.")
        }
    }

    private func reload() {
        activity = MCPActivityLog.entries()
    }

    private func callRow(_ entry: MCPActivityEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.horizontal.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.tool)
                    .font(.system(.callout, design: .monospaced))
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(DisplayFormat.date(entry.timestamp) ?? entry.timestamp)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Opens the MCP activity window from the settings pane.
struct OpenMCPActivityButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: WindowID.mcpActivity)
        } label: {
            Label("Open the activity window", systemImage: "list.bullet.rectangle")
        }
    }
}
