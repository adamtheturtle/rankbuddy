//
//  SettingsView+Accounts.swift
//  rankbuddy-macos
//

import BuddyAppKit
import SwiftUI

/// The Accounts settings pane: a Mail-style master-detail (#71). A sidebar lists the
/// configured accounts with a segmented add/remove control at its foot, and the selected
/// account's editor is shown inline in the detail pane rather than in a modal sheet.
struct AccountsSettingsView: View {
    @Environment(AccountStore.self) private var store

    /// The account selected in the sidebar, or `nil` when composing a new one / nothing selected.
    @State private var selectedID: Account.ID?
    /// True while the detail pane shows a blank editor for a not-yet-saved account.
    @State private var addingNew = false
    @State private var accountPendingRemoval: Account?

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
            detail
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
        }
        // Land on the active account when the pane opens, as PadBuddy does.
        .onAppear {
            if selectedID == nil, !addingNew {
                selectedID = store.currentAccountID ?? store.accounts.first?.id
            }
        }
        .alert("Remove Account?", isPresented: removalAlertPresented) {
            Button("Remove", role: .destructive) { removePendingAccount() }
            Button("Cancel", role: .cancel) { accountPendingRemoval = nil }
        } message: {
            Text("Remove \(accountPendingRemoval?.label ?? "this account") from RankBuddy?")
        }
    }

    /// The account matching the current sidebar selection, if it still exists.
    private var selectedAccount: Account? {
        guard let selectedID else { return nil }

        return store.accounts.first { $0.id == selectedID }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: sidebarSelection) {
            ForEach(store.accounts) { account in
                AccountRow(account: account, isCurrent: account.id == store.currentAccountID)
                    .tag(account.id)
            }
        }
        .overlay {
            if store.accounts.isEmpty {
                ContentUnavailableView("No Accounts", systemImage: "person.crop.circle.badge.plus")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            addRemoveControl
        }
    }

    /// A `List` selection binding that also leaves "add new" mode whenever a row is picked.
    private var sidebarSelection: Binding<Account.ID?> {
        Binding(
            get: { addingNew ? nil : selectedID },
            set: { newValue in
                if let newValue {
                    addingNew = false
                    selectedID = newValue
                }
            }
        )
    }

    /// PadBuddy's segmented +/− control at the sidebar foot.
    private var addRemoveControl: some View {
        HStack(spacing: 0) {
            Button {
                addingNew = true
                selectedID = nil
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 20)
            }
            .help("Add an account")
            .accessibilityLabel("Add account")

            Divider().frame(height: 16)

            Button {
                confirmRemoveSelected()
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 20)
            }
            .help("Remove the selected account")
            .accessibilityLabel("Remove account")
            .disabled(selectedAccount == nil)

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if addingNew {
            AccountEditor(existing: nil, embedded: true) { savedID in
                addingNew = false
                if let savedID { selectedID = savedID }
            }
        } else if let account = selectedAccount {
            VStack(spacing: 0) {
                accountDetailHeader(account)
                Divider()
                // `.id` re-creates the editor (and its field state) when the selection changes,
                // since SwiftUI reuses the view instance across a binding change.
                AccountEditor(existing: account, embedded: true) { _ in }
                    .id(account.id)
            }
        } else {
            emptyDetail
        }
    }

    /// The detail header: the account's identity plus a Current badge or "Use This Account".
    private func accountDetailHeader(_ account: Account) -> some View {
        HStack(spacing: 10) {
            Image(systemName: account.displayIcon)
                .font(.title)
                .foregroundStyle(account.tintColor ?? .accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.label).font(.headline)
                Text(account.userEmail ?? account.baseURL.host() ?? account.baseURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if account.id == store.currentAccountID {
                Label("Current", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Use This Account") { store.currentAccountID = account.id }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            ContentUnavailableView {
                Label("No Account Selected", systemImage: "person.crop.circle")
            } description: {
                Text("Add a HackerRank account to get started, then select it to edit.")
            } actions: {
                GetTokenLink()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private var removalAlertPresented: Binding<Bool> {
        Binding(
            get: { accountPendingRemoval != nil },
            set: { if !$0 { accountPendingRemoval = nil } }
        )
    }

    private func confirmRemoveSelected() {
        accountPendingRemoval = selectedAccount
    }

    /// Removes the confirmed account and moves the selection to a safe neighbour.
    private func removePendingAccount() {
        guard let removed = accountPendingRemoval else { return }

        let remaining = store.accounts.filter { $0.id != removed.id }
        store.remove(id: removed.id)
        selectedID = store.currentAccountID ?? remaining.first?.id
        addingNew = false
        accountPendingRemoval = nil
    }
}

#Preview("With accounts") {
    AccountsSettingsView()
        .environment(AccountStore.rankBuddy(
            isTesting: true,
            seed: [
                Account(label: "Work", token: "t", userEmail: "me@work.com", iconSymbol: "briefcase"),
                .demo
            ]
        ))
        .environment(AccountHealthMonitor())
        .frame(width: 520, height: 380)
}

#Preview("Empty") {
    AccountsSettingsView()
        .environment(AccountStore.rankBuddy(isTesting: true))
        .environment(AccountHealthMonitor())
        .frame(width: 520, height: 380)
}
