//
//  MenuBarContent.swift
//  rankbuddy-macos
//

import AppKit
import BuddyAppKit
import HackerRankKit
import SwiftUI

/// The contents of the menu bar extra: account-aware status, quick navigation to each
/// section, and common actions.
///
/// Selecting a section sets the persisted selection and brings the main window forward;
/// switching accounts retargets the whole app at the chosen account. Everything reads the
/// shared `AccountStore`, so the menu never spins up a second account/request stack (#23).
struct MenuBarContent: View {
    @AppStorage("selectedSection") private var selection: SidebarSection = .tests
    @AppStorage(MenuBarPreferences.recentCountKey) private var recentCount = MenuBarPreferences.defaultRecentCount
    @AppStorage(MenuBarPreferences.activeOnlyKey) private var activeOnly = false
    @Environment(\.openWindow) private var openWindow
    @Environment(AccountStore.self) private var store
    @State private var createSheet: MenuBarCreateSheet?

    var body: some View {
        Group {
            menuItems
        }
        .sheet(item: $createSheet) { sheet in
            switch sheet {
            case let .quickPad(account):
                NewQuickPadSheet(account: account) { finishCreate(in: .interviews) }
            case let .scheduledInterview(account):
                ScheduleInterviewSheet(account: account) { finishCreate(in: .interviews) }
            case let .test(account):
                TestEditorSheet(account: account, mode: .create) { finishCreate(in: .tests) }
            }
        }
    }

    @ViewBuilder private var menuItems: some View {
        if NetworkMonitor.shared.isOffline {
            Label("Offline", systemImage: "wifi.slash")
            Divider()
        }

        accountSection

        createSection

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

        // Help and About mirror PadBuddy's menu-bar footer (#88), so the common entry points
        // are reachable without first opening the main window.
        Link("Get a Token", destination: Self.tokenURL)

        Button("About RankBuddy") { AboutPanel.show() }

        Divider()

        Button("Quit RankBuddy") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Where a HackerRank for Work personal access token is generated (mirrors `GetTokenLink`).
    private static let tokenURL = URL(string: "https://www.hackerrank.com/work/settings/token") ?? Account.defaultBaseURL

    private var writableAccount: Account? {
        guard !NetworkMonitor.shared.isOffline, !store.isMergedView else { return nil }

        return store.currentAccount
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
            // Multiple accounts: show the current target (or the merged view) and let the user
            // switch — including to the combined "All Accounts" view — mirroring PadBuddy's
            // Switch Account menu, with each account's own icon (#110, #17, #64).
            Menu("Account: \(store.isMergedView ? "All Accounts" : (store.currentAccount?.label ?? "None"))") {
                Button {
                    store.showAllAccounts = true
                } label: {
                    if store.isMergedView {
                        Label("All Accounts", systemImage: "checkmark")
                    } else {
                        Text("All Accounts")
                    }
                }

                Divider()

                ForEach(store.accounts) { account in
                    Button {
                        store.showAllAccounts = false
                        store.currentAccountID = account.id
                    } label: {
                        if !store.isMergedView, account.id == store.currentAccount?.id {
                            Label(account.label, systemImage: "checkmark")
                        } else {
                            Label(account.label, systemImage: account.displayIcon)
                        }
                    }
                }
            }
        }
    }

    /// PadBuddy-style create actions from the menu bar (#121), reusing the existing write sheets
    /// so the menu does not grow a separate HackerRank write path.
    @ViewBuilder private var createSection: some View {
        if !store.accounts.isEmpty {
            Divider()
            Section("Create") {
                Button {
                    if let account = writableAccount { createSheet = .quickPad(account) }
                } label: {
                    Label("New QuickPad…", systemImage: "bolt")
                }
                .disabled(writableAccount == nil)

                Button {
                    if let account = writableAccount { createSheet = .scheduledInterview(account) }
                } label: {
                    Label("Schedule Interview…", systemImage: "calendar.badge.plus")
                }
                .disabled(writableAccount == nil)

                Button {
                    if let account = writableAccount { createSheet = .test(account) }
                } label: {
                    Label("New Test…", systemImage: "doc.badge.plus")
                }
                .disabled(writableAccount == nil)

                if store.isMergedView {
                    Text("Choose an account to create items")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Recent items the current account has listed, read from the on-disk cache the main
    /// window populates — no second network stack (#23). Hidden when there's nothing cached.
    @ViewBuilder private var recentSection: some View {
        if let account = store.currentAccount, recentCount > 0 {
            let cached = RecentActivityStore.shared.recentAll(account: account.id)
            let recents = activeOnly ? cached.filter(\.isActiveOrUpcoming) : cached
            if !recents.isEmpty {
                Divider()
                Section(activeOnly ? "Active & Upcoming" : "Recent") {
                    ForEach(recents.prefix(recentCount)) { item in
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

    private func finishCreate(in section: SidebarSection) {
        selection = section
        showMainWindow()
    }

    private func showMainWindow() {
        openWindow(id: WindowID.main)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

/// The create sheet the menu bar is currently presenting (#121). The account is captured when
/// the action is chosen so a later account switch does not retarget an already-open sheet.
private enum MenuBarCreateSheet: Identifiable {
    case quickPad(Account)
    case scheduledInterview(Account)
    case test(Account)

    var id: String {
        switch self {
        case let .quickPad(account): "quick-pad-\(account.id.uuidString)"
        case let .scheduledInterview(account): "scheduled-interview-\(account.id.uuidString)"
        case let .test(account): "test-\(account.id.uuidString)"
        }
    }
}
