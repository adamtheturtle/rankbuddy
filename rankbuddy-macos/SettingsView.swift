import BuddyAppKit
import SwiftUI

/// The app's Settings scene: manage HackerRank accounts (add, edit, remove).
struct SettingsView: View {
    @Environment(AccountStore.self) private var store
    @State private var editing: AccountEditingTarget?
    @AppStorage(WriteActions.defaultsKey) private var writeActionsEnabled = false
    @AppStorage(AppAppearance.defaultsKey) private var appearance: AppAppearance = .system
    @AppStorage(MenuBarPreferences.recentCountKey)
    private var menuBarRecentCount = MenuBarPreferences.defaultRecentCount

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

            mcpTab
                .tabItem {
                    Label("MCP", systemImage: "terminal")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 520, height: 380)
        .sheet(item: $editing) { target in
            NavigationStack {
                AccountEditor(existing: target.account)
                    .environment(store)
            }
        }
    }

    private var generalTab: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Stepper(
                    "Recent items in the menu bar: \(menuBarRecentCount)",
                    value: $menuBarRecentCount,
                    in: 0 ... MenuBarPreferences.maxRecentCount
                )
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("How many recently viewed items the menu bar lists. Set to 0 to hide the Recent section.")
            }
        }
        .formStyle(.grouped)
    }

    private var accountsTab: some View {
        Form {
            Section {
                if store.accounts.isEmpty {
                    Text("No accounts yet. Add a HackerRank account to get started.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.accounts) { account in
                        AccountRow(account: account, isCurrent: account.id == store.currentAccountID)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = .edit(account) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("Edit this account")
                            .contextMenu {
                                Button("Edit") { editing = .edit(account) }
                                Button("Remove", role: .destructive) {
                                    store.remove(id: account.id)
                                }
                            }
                    }
                }
            }

            Section {
                Button("Add Account…") { editing = .add }

                // A one-click demo account backed by the in-process fixtures, so the app can
                // be explored without a real token (#10). Offered only until one exists.
                if !store.accounts.contains(where: \.isMock) {
                    Button("Add Demo Account") { store.add(.demo) }
                }
            } footer: {
                Text("The demo account shows sample data from the built-in mock server — no HackerRank token required.")
            }

            Section {
                Toggle("Enable write actions", isOn: $writeActionsEnabled)
            } header: {
                Text("Actions")
            } footer: {
                Text("RankBuddy is read-only by default. Turn this on to allow actions that " +
                    "change data on HackerRank, such as inviting a candidate to a test. Each " +
                    "action still confirms before it runs.")
            }
        }
        .formStyle(.grouped)
    }

    private var mcpTab: some View {
        Form {
            Section("Model Context Protocol") {
                Text("RankBuddy can act as a read-only MCP server, so an AI assistant " +
                    "(e.g. Claude Desktop) can browse the selected account's tests, candidates, " +
                    "questions, and interviews.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Text(MCPSetup.clientConfigJSON())
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Clipboard.copy(MCPSetup.clientConfigJSON())
                } label: {
                    Label("Copy Configuration", systemImage: "doc.on.doc")
                }
            } header: {
                Text("Client configuration")
            } footer: {
                Text("Add this to your MCP client's config (for Claude Desktop, " +
                    "claude_desktop_config.json) and restart the client. The server reads the " +
                    "account currently selected in RankBuddy and never exposes your token.")
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        Form {
            Section("RankBuddy") {
                LabeledContent("Version", value: Self.appVersion)
                Text("A native macOS browser for HackerRank for Work tests, candidates, questions, and interviews.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    /// The app's marketing version and build number, e.g. "1.0 (12)".
    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

/// One row in the accounts list.
struct AccountRow: View {
    let account: Account
    let isCurrent: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.label).font(.headline)
                Text(account.baseURL.host() ?? account.baseURL.absoluteString)
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

/// What the editor sheet is presenting: a new account or an existing one.
enum AccountEditingTarget: Identifiable {
    case add
    case edit(Account)

    var id: String {
        switch self {
        case .add: "add"
        case let .edit(account): account.id.uuidString
        }
    }

    var account: Account? {
        switch self {
        case .add: nil
        case let .edit(account): account
        }
    }
}

#Preview {
    SettingsView()
        .environment(AccountStore.rankBuddy(isTesting: true))
}
