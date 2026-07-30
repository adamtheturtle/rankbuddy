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
    @State private var recovery = AccountDataRecovery.shared

    /// The account selected in the sidebar, or `nil` when composing a new one / nothing selected.
    @State private var selectedID: Account.ID?
    /// True while the detail pane shows a blank editor for a not-yet-saved account.
    @State private var addingNew = false
    @State private var accountPendingRemoval: Account?
    @State private var editorIsDirty = false
    @State private var pendingEditorTransition: EditorTransition?

    private enum EditorTransition {
        case select(Account.ID)
        case add
    }

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
            Text(
                "Remove \(accountPendingRemoval?.label ?? "this account") from RankBuddy? " +
                    "Its saved credentials, recent activity, and other local account data will be deleted. " +
                    "This does not delete data from HackerRank."
            )
        }
        .alert("Discard Unsaved Changes?", isPresented: discardAlertPresented) {
            Button("Discard Changes", role: .destructive) { performPendingEditorTransition() }
            Button("Cancel", role: .cancel) { pendingEditorTransition = nil }
        } message: {
            Text("Your changes to this account have not been saved.")
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
                if recovery.issue != nil {
                    ContentUnavailableView("Account Data Unreadable", systemImage: "key.viewfinder")
                } else {
                    ContentUnavailableView("No Accounts", systemImage: "person.crop.circle.badge.plus")
                }
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
                    requestEditorTransition(.select(newValue))
                }
            }
        )
    }

    /// PadBuddy's segmented +/− control at the sidebar foot.
    private var addRemoveControl: some View {
        HStack(spacing: 0) {
            Button {
                requestEditorTransition(.add)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 20)
            }
            .help("Add an account")
            .accessibilityLabel("Add account")
            .disabled(recovery.issue?.replacementAllowed == false)

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
        if let issue = recovery.issue, !addingNew {
            recoveryDetail(issue)
        } else if addingNew {
            AccountEditor(existing: nil, embedded: true) { savedID in
                addingNew = false
                if let savedID { selectedID = savedID }
            } onDirtyChange: { editorIsDirty = $0 }
        } else if let account = selectedAccount {
            VStack(spacing: 0) {
                accountDetailHeader(account)
                Divider()
                // `.id` re-creates the editor (and its field state) when the selection changes,
                // since SwiftUI reuses the view instance across a binding change.
                AccountEditor(
                    existing: account,
                    embedded: true,
                    onFinish: { _ in },
                    onDirtyChange: { editorIsDirty = $0 }
                )
                .id(account.id)
            }
        } else {
            emptyDetail
        }
    }

    private func recoveryDetail(_ issue: AccountDataRecovery.Issue) -> some View {
        ContentUnavailableView {
            Label("Saved Accounts Need Recovery", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            if issue.replacementAllowed {
                Text("The saved account JSON could not be decoded. RankBuddy retained the original " +
                    "payload in the Keychain before allowing replacement. Add the accounts again " +
                    "when ready; existing token data remains available in the recovery copy.")
            } else {
                Text("The saved account JSON could not be decoded, and its recovery copy could not " +
                    "be written to the Keychain. Adding accounts is disabled to avoid overwriting it.")
            }
        } actions: {
            if issue.replacementAllowed {
                Button("Add Account…") {
                    addingNew = true
                    selectedID = nil
                }
                .buttonStyle(.borderedProminent)
            }
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

    private var discardAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingEditorTransition != nil },
            set: { if !$0 { pendingEditorTransition = nil } }
        )
    }

    private func requestEditorTransition(_ transition: EditorTransition) {
        switch transition {
        case let .select(id) where !addingNew && selectedID == id:
            return
        case .add where addingNew:
            return
        default:
            break
        }

        guard editorIsDirty else {
            applyEditorTransition(transition)
            return
        }

        pendingEditorTransition = transition
    }

    private func performPendingEditorTransition() {
        guard let transition = pendingEditorTransition else { return }

        pendingEditorTransition = nil
        applyEditorTransition(transition)
    }

    private func applyEditorTransition(_ transition: EditorTransition) {
        editorIsDirty = false
        switch transition {
        case let .select(id):
            addingNew = false
            selectedID = id

        case .add:
            addingNew = true
            selectedID = nil
        }
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
