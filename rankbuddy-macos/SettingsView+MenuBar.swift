//
//  SettingsView+MenuBar.swift
//  rankbuddy-macos
//

import SwiftUI

extension SettingsView {
    /// The Menu Bar tab (#114): just the menu-bar extra's recent list, mirroring PadBuddy's minimal
    /// Menu Bar tab. The Dock-badge / background-update controls live in General (see
    /// `interviewUpdatesSection`), as PadBuddy keeps its equivalents there. In a separate file so it
    /// stays off `SettingsView`'s body/file-length budget, like the MCP and Browser tabs.
    var menuBarTab: some View {
        Form {
            // The tab is always present so the Settings layout stays stable; when the menu-bar
            // icon is turned off (Dock-only mode) the controls below have no effect, so explain
            // that and disable them rather than making the whole tab vanish and reappear.
            if !presence.showsMenuBarIcon {
                Section {
                    Text("The menu-bar icon is turned off. Turn it on under General, " +
                        "“Show RankBuddy in”, to use these settings.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Stepper(value: $menuBarRecentCount, in: 0 ... MenuBarPreferences.maxRecentCount) {
                    HStack {
                        Text("Recent items in the menu bar")
                        Spacer()
                        Text("\(menuBarRecentCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("Show only active or upcoming items", isOn: $menuBarActiveOnly)
            }
        }
        .formStyle(.grouped)
        .disabled(!presence.showsMenuBarIcon)
    }

    /// The Dock-badge / background-update controls, shown on the General tab (mirroring PadBuddy,
    /// which keeps its Dock badge + notification options in General). Extracted to a property so it
    /// stays off `generalTab`'s body-length budget, like `mcpConfigSections`.
    var interviewUpdatesSection: some View {
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
        } footer: {
            Text("Keeps a count of scheduled interviews on the Dock icon and, optionally, " +
                "posts a notification when new interviews appear, refreshed in the background " +
                "even when no window is open. Badge counts the current account or every account.")
        }
    }
}
