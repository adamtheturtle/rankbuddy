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

        activeSection

        createSection

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

        // A nested Help menu mirrors PadBuddy's menu-bar footer (#88): the docs, token, and
        // feedback entry points are reachable without first opening the main window.
        Menu("Help") {
            Link("HackerRank API Documentation", destination: RankBuddyLinks.apiDocs)
            Link("Get a Token", destination: RankBuddyLinks.tokenURL)
            Divider()
            Link("Send Feedback…", destination: RankBuddyLinks.feedbackMailto)
        }

        Button("About RankBuddy") { AboutPanel.show() }

        Divider()

        Button("Quit RankBuddy") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Where a HackerRank for Work personal access token is generated (mirrors `GetTokenLink`).
    private static let tokenURL = URL(string: "https://www.hackerrank.com/work/settings/token")
        ?? Account.defaultBaseURL

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

    /// PadBuddy-style create actions from the menu bar (#121). "New Pad" creates and opens in
    /// the browser directly (PadBuddy-style); the interview/test flows reuse the existing write
    /// sheets so the menu does not grow a separate HackerRank write path.
    @ViewBuilder private var createSection: some View {
        if !store.accounts.isEmpty {
            Divider()
            Section("Create") {
                Button {
                    if let account = writableAccount { Task { await createPad(in: account) } }
                } label: {
                    Label("New Pad…", systemImage: "bolt")
                }
                .keyboardShortcut("n")
                .disabled(writableAccount == nil)

                // New Pad opens the created pad in the user's browser, which may be signed into a
                // different HackerRank account, so warn first — mirroring PadBuddy's note (#602).
                if writableAccount != nil {
                    Text("Opens in your browser's signed-in account")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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

    /// Interviews/tests that are live or upcoming right now, pinned near the top of the menu so
    /// an in-progress session is the first thing you see — mirroring PadBuddy's "Active Interviews"
    /// block (#593). Drawn from the same on-disk cache as the rest of the menu, so it adds no
    /// network work (#23). Suppressed when the Recent section is already filtered to active items
    /// (the `activeOnly` toggle), so the two don't render an identical list twice.
    @ViewBuilder private var activeSection: some View {
        if !activeOnly, let account = store.currentAccount, recentCount > 0 {
            let active = RecentActivityStore.shared.recentAll(account: account.id).filter(\.isActiveOrUpcoming)
            if !active.isEmpty {
                Divider()
                Section("Active & Upcoming") {
                    itemRows(active, account: account) { _ in "dot.radiowaves.left.and.right" }
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
                    itemRows(recents, account: account) { $0.collection.systemImage }
                }
            }
        }
    }

    /// Renders a list of cached recent items, capped at `recentCount` with a "…N more" overflow
    /// line (mirroring PadBuddy). Each row deep-links to the item in-app and brings the window
    /// forward. `icon` picks the SF Symbol per item so the active and recent sections can differ.
    @ViewBuilder private func itemRows(
        _ items: [RecentItem],
        account: Account,
        icon: @escaping (RecentItem) -> String
    ) -> some View {
        ForEach(items.prefix(recentCount)) { item in
            Button {
                RankBuddyDeepLink.open(
                    collection: item.collection,
                    accountID: account.id.uuidString,
                    itemID: item.id
                )
                showMainWindow()
            } label: {
                Label(item.title, systemImage: icon(item))
            }
        }
        if items.count > recentCount {
            Text("…\(items.count - recentCount) more")
                .foregroundStyle(.secondary)
        }
    }

    /// Creates an instant Pad for `account` and opens it in the browser, mirroring PadBuddy's
    /// menu-bar "New Pad" (which creates and opens directly). A sheet can't be used here:
    /// SwiftUI sheets don't present from a `.menu`-style `MenuBarExtra`, so the fuller
    /// `NewPadSheet` flow stays on the main window.
    private func createPad(in account: Account) async {
        do {
            let created = try await HackerRankClient(account: account).createPad()
            if !account.isMock, let rawURL = created.url, let url = URL.remoteWebURL(from: rawURL) {
                // Success: open the new pad in the browser. No need to steal focus with the
                // main window — `BrowserSettings.open` brings the browser forward instead.
                BrowserSettings.open(url)
            } else {
                // Demo account (or a missing URL): nothing to open, so surface the item in-app.
                finishCreate(in: .interviews)
            }
        } catch {
            // Offline/auth failure: bring the main window forward on Interviews so the failure
            // isn't silent and the user can retry from the full create flow.
            finishCreate(in: .interviews)
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

/// Help-menu destinations for the menu bar, mirroring PadBuddy's `CoderPadLinks` (#88). This is
/// an unofficial client, so feedback goes to the developer rather than HackerRank.
enum RankBuddyLinks {
    /// Where a HackerRank for Work personal access token is generated (mirrors `GetTokenLink`).
    static let tokenURL = URL(string: "https://www.hackerrank.com/work/settings/token") ?? Account.defaultBaseURL

    /// HackerRank for Work's REST API documentation.
    static let apiDocs = URL(string: "https://www.hackerrank.com/work/apidocs") ?? Account.defaultBaseURL

    static let feedbackEmail = "hello@adamdangoor.com"

    /// A pre-filled feedback email addressed to the developer, with the app and macOS versions
    /// appended so each report carries the context needed to act on it. Falls back to a bare
    /// mailto if the query somehow fails to encode.
    static var feedbackMailto: URL {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let body = """


        ---
        App version: \(version) (\(build))
        macOS: \(osVersion)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "RankBuddy for Mac feedback"),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url ?? URL(string: "mailto:\(feedbackEmail)") ?? apiDocs
    }
}

/// The create sheet the menu bar is currently presenting (#121). The account is captured when
/// the action is chosen so a later account switch does not retarget an already-open sheet.
private enum MenuBarCreateSheet: Identifiable {
    case scheduledInterview(Account)
    case test(Account)

    var id: String {
        switch self {
        case let .scheduledInterview(account): "scheduled-interview-\(account.id.uuidString)"
        case let .test(account): "test-\(account.id.uuidString)"
        }
    }
}
