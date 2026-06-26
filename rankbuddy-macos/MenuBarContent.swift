import AppKit
import BuddyAppKit
import SwiftUI

/// The contents of the menu bar extra: account-aware status, quick navigation to each
/// section, and common actions.
///
/// Selecting a section sets the persisted selection and brings the main window forward;
/// switching accounts retargets the whole app at the chosen account. Everything reads the
/// shared `AccountStore`, so the menu never spins up a second account/request stack (#23).
struct MenuBarContent: View {
    @AppStorage("selectedSection") private var selection: SidebarSection = .tests
    @Environment(\.openWindow) private var openWindow
    @Environment(AccountStore.self) private var store

    var body: some View {
        if NetworkMonitor.shared.isOffline {
            Label("Offline", systemImage: "wifi.slash")
            Divider()
        }

        accountSection

        Divider()

        ForEach(SidebarSection.allCases) { section in
            Button {
                selection = section
                showMainWindow()
            } label: {
                Label(section.title, systemImage: section.systemImage)
            }
        }

        recentSection

        Divider()

        Button("Open RankBuddy") { showMainWindow() }

        // SettingsLink opens the existing Settings scene (or orders it to the front if it is
        // already open), so it never creates a duplicate Settings window.
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit RankBuddy") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Surfaces which account the menu's actions target, with an understandable state for
    /// the no-account and multi-account cases.
    @ViewBuilder private var accountSection: some View {
        if store.accounts.isEmpty {
            // Empty state: make it obvious there is nothing to act on and how to fix it.
            Text("No account configured")
            SettingsLink {
                Text("Add Account…")
            }
        } else if store.accounts.count == 1 {
            // A single account: a plain, non-interactive label is enough.
            Text("Account: \(store.currentAccount?.label ?? "")")
        } else {
            // Multiple accounts: show the current target and let the user switch it.
            Menu("Account: \(store.currentAccount?.label ?? "None")") {
                ForEach(store.accounts) { account in
                    Button {
                        store.currentAccountID = account.id
                    } label: {
                        if account.id == store.currentAccount?.id {
                            Label(account.label, systemImage: "checkmark")
                        } else {
                            Text(account.label)
                        }
                    }
                }
            }
        }
    }

    /// Recent items the current account has listed, read from the on-disk cache the main
    /// window populates — no second network stack (#23). Hidden when there's nothing cached.
    @ViewBuilder private var recentSection: some View {
        if let account = store.currentAccount {
            let recents = RecentActivityStore.shared.recentAll(account: account.id)
            if !recents.isEmpty {
                Divider()
                Section("Recent") {
                    ForEach(recents.prefix(RecentActivityStore.perCollectionLimit)) { item in
                        Button {
                            RankBuddyDeepLink.open(
                                collection: item.collection,
                                accountID: account.id.uuidString,
                                itemID: item.id
                            )
                            showMainWindow()
                        } label: {
                            Label(item.title, systemImage: item.collection.systemImage)
                        }
                    }
                }
            }
        }
    }

    private func showMainWindow() {
        openWindow(id: WindowID.main)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
