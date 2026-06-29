//
//  SettingsView+MenuBar.swift
//  rankbuddy-macos
//

import SwiftUI

extension SettingsView {
    /// The Menu Bar tab (#114): the menu-bar extra's recent list plus the Dock-badge / background
    /// update settings, grouped on their own tab (mirroring PadBuddy) instead of crowding General.
    /// In a separate file so it stays off `SettingsView`'s body/file-length budget, like the MCP
    /// and Browser tabs.
    var menuBarTab: some View {
        Form {
            if presence.showsMenuBarIcon {
                Section {
                    Stepper(
                        "Recent items in the menu bar: \(menuBarRecentCount)",
                        value: $menuBarRecentCount,
                        in: 0 ... MenuBarPreferences.maxRecentCount
                    )

                    Toggle("Show only active or upcoming items", isOn: $menuBarActiveOnly)
                } header: {
                    Text("Menu Bar")
                } footer: {
                    Text("How many recently viewed items the menu bar lists (0 hides the Recent section). " +
                        "When filtered, it shows only open tests and scheduled interviews.")
                }
            } else {
                Section {
                    Text("Show RankBuddy in the Menu Bar (in General) to list recent items there.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Toggle("Show upcoming interviews on the Dock icon", isOn: $backgroundUpdates)
                    .onChange(of: backgroundUpdates) { _, enabled in
                        if enabled { LivenessMonitor.shared.requestBadgeAuthorization() }
                        Task { await LivenessMonitor.shared.sweep(store: store) }
                    }

                Toggle("Notify me about new interviews", isOn: $notifyNewInterviews)
                    .onChange(of: notifyNewInterviews) { _, enabled in
                        if enabled { LivenessNotifier.shared.requestAuthorization() }
                    }
                    .disabled(!backgroundUpdates)

                Picker("Check every", selection: $refreshMinutes) {
                    ForEach(LivenessSettings.intervalOptions, id: \.self) { minutes in
                        Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes)
                    }
                }
                .disabled(!backgroundUpdates)

                Picker("Badge counts", selection: $dockBadgeScope) {
                    ForEach(DockBadgeScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .disabled(!backgroundUpdates)
                .onChange(of: dockBadgeScope) {
                    Task { await LivenessMonitor.shared.sweep(store: store) }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Keeps a count of scheduled interviews on the Dock icon and, optionally, " +
                    "posts a notification when new interviews appear, refreshed in the background " +
                    "even when no window is open. Badge counts the current account or every account.")
            }
        }
        .formStyle(.grouped)
    }
}
