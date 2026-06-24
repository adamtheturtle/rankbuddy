import BuddyAppKit
import SwiftUI

/// The app's Settings scene: manage HackerRank accounts (add, edit, remove).
struct SettingsView: View {
    @Environment(AccountStore.self) private var store
    @State private var editing: AccountEditingTarget?

    var body: some View {
        TabView {
            accountsTab
                .tabItem {
                    Label("Accounts", systemImage: "person.crop.circle")
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
