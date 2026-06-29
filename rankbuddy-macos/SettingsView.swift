//
//  SettingsView.swift
//  rankbuddy-macos
//

import BuddyAppKit
import SwiftUI

/// The app's Settings scene: manage HackerRank accounts (add, edit, remove).
struct SettingsView: View {
    @Environment(AccountStore.self) private var store
    @AppStorage(AppAppearance.defaultsKey) private var appearance: AppAppearance = .system
    @AppStorage(AppPresence.defaultsKey) private var presence: AppPresence = .both
    @AppStorage(MenuBarPreferences.recentCountKey)
    private var menuBarRecentCount = MenuBarPreferences.defaultRecentCount
    @AppStorage(MenuBarPreferences.activeOnlyKey) private var menuBarActiveOnly = false
    @AppStorage(LivenessSettings.backgroundUpdatesKey) private var backgroundUpdates = false
    @AppStorage(LivenessSettings.notifyKey) private var notifyNewInterviews = false
    @AppStorage(LivenessSettings.intervalMinutesKey)
    private var refreshMinutes = LivenessSettings.defaultIntervalMinutes
    @AppStorage(LivenessSettings.dockScopeKey) private var dockBadgeScope: DockBadgeScope = .currentAccount
    @AppStorage(BiometricAuth.revealSettingKey) private var biometricReveal = false
    @AppStorage(GeneralSettings.refreshSecondsKey)
    private var listRefreshSeconds = GeneralSettings.defaultRefreshSeconds
    @AppStorage(MCPServerSettings.enabledKey) private var mcpServerEnabled = false
    @AppStorage(MCPServerSettings.allowWritesKey) private var mcpAllowWrites = false
    @AppStorage(BrowserSettings.defaultBrowserKey) var defaultBrowserID = ""
    @AppStorage(BrowserSettings.backgroundKey) var openLinksInBackground = false
    // `mcpActivity`/`mcpClient`/`installedBrowsers` are internal so the MCP and Browser
    // sections (separate files, for file_length) can read them (#74, #63).
    @State var mcpActivity: [MCPActivityEntry] = []
    @State var mcpClient: MCPClient = .claudeDesktop
    @State var installedBrowsers: [BrowserSettings.Browser] = []
    @State private var loginItemError: String?

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            accountsTab
                .tabItem {
                    Label("Accounts", systemImage: "person.crop.circle")
                }

            browserTab
                .tabItem {
                    Label("Browser", systemImage: "safari")
                }

            mcpTab
                .tabItem {
                    Label("MCP", systemImage: "terminal")
                }
        }
        .frame(width: 520, height: 380)
        .alert("Couldn’t change the login item", isPresented: loginItemErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loginItemError ?? "")
        }
    }

    private var generalTab: some View {
        Form {
            Section("Appearance") {
                AppearancePicker(selection: $appearance)
                    .padding(.vertical, 4)
            }

            Section {
                Picker("Show RankBuddy in", selection: $presence) {
                    ForEach(AppPresence.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } header: {
                Text("Presence")
            } footer: {
                Text("Choose whether RankBuddy appears in the Dock, the Menu Bar, or both. " +
                    "Menu Bar only hides the Dock icon for a lightweight, always-available app.")
            }

            Section {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
            } header: {
                Text("Startup")
            } footer: {
                Text("Open RankBuddy automatically when you log in to your Mac.")
            }

            Section {
                Stepper(
                    "Auto-refresh lists: \(GeneralSettings.refreshIntervalLabel(listRefreshSeconds))",
                    value: $listRefreshSeconds,
                    in: 0 ... GeneralSettings.maxRefreshSeconds,
                    step: GeneralSettings.refreshStep
                )
            } header: {
                Text("Lists")
            } footer: {
                Text("Periodically reload the list you're viewing. Off by default; refreshes only " +
                    "while you're on a list (not inside an item) and haven't scrolled past the first page.")
            }

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

            Section {
                Toggle("Require Touch ID to reveal a token", isOn: biometricRevealBinding)
            } header: {
                Text("Security")
            } footer: {
                Text("When on, revealing an account's token in the editor asks for Touch ID first. " +
                    "Turning this off asks for Touch ID too, so it can't be disabled at an unlocked Mac.")
            }
        }
        .formStyle(.grouped)
    }

    private var accountsTab: some View {
        AccountsSettingsView()
    }

    private var mcpTab: some View {
        Form {
            Section {
                Toggle("Enable the MCP server", isOn: $mcpServerEnabled)
            } header: {
                Text("Model Context Protocol")
            } footer: {
                Text("RankBuddy can act as a read-only MCP server, so an AI assistant " +
                    "(e.g. Claude Desktop) can browse the selected account's tests, candidates, " +
                    "questions, and interviews. It's off until you turn it on here.")
            }

            if mcpServerEnabled {
                Section {
                    Toggle("Allow the MCP server to make changes", isOn: $mcpAllowWrites)
                } footer: {
                    Text("Off by default. When on, the server also exposes write tools: creating " +
                        "and deleting tests, inviting candidates, creating users/teams, and scheduling " +
                        "interviews. Only enable this if you trust the assistant with live data. Takes " +
                        "effect after you restart the assistant.")
                }

                mcpConfigSections
            }
        }
        .formStyle(.grouped)
        .onAppear { mcpActivity = MCPActivityLog.entries() }
    }
}

/// Setting bindings, in an extension so they don't count toward `SettingsView`'s body length.
private extension SettingsView {
    var loginItemErrorPresented: Binding<Bool> {
        Binding(get: { loginItemError != nil }, set: { if !$0 { loginItemError = nil } })
    }

    /// The "Launch at login" state, with the system as the source of truth: `get` reads the
    /// live `SMAppService` status and `set` registers/unregisters, surfacing any error. On
    /// failure the live status is unchanged, so the toggle reflects reality without a manual
    /// snap-back (#62).
    var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { LoginItem.isEnabled },
            set: { enabled in
                do {
                    try LoginItem.setEnabled(enabled)
                } catch {
                    loginItemError = error.localizedDescription
                }
            }
        )
    }

    /// The "Require Touch ID to reveal a token" state. Enabling is free; disabling first
    /// requires a successful device-owner auth, so the protection can't simply be switched off
    /// at an unlocked Mac (#65). A failed/cancelled prompt leaves it on.
    var biometricRevealBinding: Binding<Bool> {
        Binding(
            get: { biometricReveal },
            set: { enabled in
                if enabled {
                    biometricReveal = true
                } else {
                    Task {
                        if await BiometricAuth.authenticateToDisableGate(
                            reason: "turn off the Touch ID requirement"
                        ) {
                            biometricReveal = false
                        }
                    }
                }
            }
        )
    }
}

/// One row in the accounts list.
struct AccountRow: View {
    let account: Account
    let isCurrent: Bool

    var body: some View {
        HStack {
            Image(systemName: account.displayIcon)
                .font(.title2)
                .foregroundStyle(account.tintColor ?? .accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.label).font(.headline)
                Text(account.userEmail ?? account.baseURL.host() ?? account.baseURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .help("Current account")
                    .accessibilityLabel("Current account")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SettingsView()
        .environment(AccountStore.rankBuddy(isTesting: true))
}
