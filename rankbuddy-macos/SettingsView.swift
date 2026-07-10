//
//  SettingsView.swift
//  rankbuddy-macos
//

import BuddyAppKit
import BuddyDesignSystem
import SwiftUI

enum SettingsTab: String {
    static let defaultsKey = "selectedSettingsTab"

    case general
    case accounts
    case browser
    case menuBar
    case mcp
}

/// The app's Settings scene: manage HackerRank accounts (add, edit, remove).
struct SettingsView: View {
    // Internal so the Menu Bar tab extension (separate file) can drive the liveness sweep (#114).
    @Environment(AccountStore.self) var store
    @AppStorage(AppAppearance.defaultsKey) private var appearance: AppAppearance = .system
    @AppStorage(AppPresence.defaultsKey) var presence: AppPresence = .both
    // The menu-bar / updates settings are internal so the Menu Bar tab (a separate file, for
    // file_length) can read them (#114), like the MCP and Browser sections.
    @AppStorage(MenuBarPreferences.recentCountKey)
    var menuBarRecentCount = MenuBarPreferences.defaultRecentCount
    @AppStorage(MenuBarPreferences.activeOnlyKey) var menuBarActiveOnly = false
    @AppStorage(LivenessSettings.backgroundUpdatesKey) var backgroundUpdates = false
    @AppStorage(LivenessSettings.notifyKey) var notifyNewInterviews = false
    @AppStorage(LivenessSettings.intervalMinutesKey)
    var refreshMinutes = LivenessSettings.defaultIntervalMinutes
    @AppStorage(LivenessSettings.dockScopeKey) var dockBadgeScope: DockBadgeScope = .currentAccount
    @AppStorage(BiometricAuth.revealSettingKey) private var biometricReveal = false
    @AppStorage(GeneralSettings.refreshSecondsKey)
    private var listRefreshSeconds = GeneralSettings.defaultRefreshSeconds
    @AppStorage(MCPServerSettings.enabledKey) private var mcpServerEnabled = false
    @AppStorage(MCPServerSettings.allowWritesKey) private var mcpAllowWrites = false
    @AppStorage(BrowserSettings.defaultBrowserKey) var defaultBrowserID = ""
    @AppStorage(BrowserSettings.backgroundKey) var openLinksInBackground = false
    @AppStorage(SettingsTab.defaultsKey) private var selectedTab: SettingsTab = .general
    // `installedBrowsers` is internal so the Browser section (a separate file, for file_length)
    // can read it (#63).
    @State var installedBrowsers: [BrowserSettings.Browser] = []
    @State private var loginItemError: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            accountsTab
                .tabItem {
                    Label("Accounts", systemImage: "person.crop.circle")
                }
                .tag(SettingsTab.accounts)

            browserTab
                .tabItem {
                    Label("Browser", systemImage: "safari")
                }
                .tag(SettingsTab.browser)

            menuBarTab
                .tabItem {
                    Label("Menu Bar", systemImage: "menubar.rectangle")
                }
                .tag(SettingsTab.menuBar)

            mcpTab
                .tabItem {
                    Label("MCP Server", systemImage: "terminal")
                }
                .tag(SettingsTab.mcp)
        }
        .frame(minWidth: 620, minHeight: 440)
        .alert("Couldn’t change the login item", isPresented: loginItemErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loginItemError ?? "")
        }
    }

    private var generalTab: some View {
        Form {
            Section {
                LabeledContent("Appearance") {
                    AppearancePicker(selection: Binding(
                        get: { appearance.colorScheme },
                        set: { appearance = AppAppearance(colorScheme: $0) }
                    ))
                }
            }

            Section {
                Picker("Show RankBuddy in", selection: $presence) {
                    ForEach(AppPresence.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } footer: {
                Text("Choose whether RankBuddy appears in the Dock, the Menu Bar, or both. " +
                    "Menu Bar only hides the Dock icon for a lightweight, always-available app.")
            }

            interviewUpdatesSection

            Section {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
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
            } footer: {
                Text("Periodically reload the list you're viewing. Off by default; refreshes only " +
                    "while you're on a list (not inside an item) and haven't scrolled past the first page.")
            }

            Section {
                Toggle("Require Touch ID to reveal a token", isOn: biometricRevealBinding)
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
                Text("The Model Context Protocol (MCP) lets AI assistants like Claude read your " +
                    "HackerRank data (your tests, candidates, questions, and interviews) so you " +
                    "can ask them about it in plain language.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("What it does")
            }

            Section {
                Toggle("Enable the MCP server", isOn: $mcpServerEnabled)
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
                        if await BiometricGate.authenticateToDisableGate(
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
