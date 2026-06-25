import BuddyAppKit
import SwiftUI

/// A compact account picker pinned to the bottom of the sidebar: it shows which account's
/// data is on screen and switches between configured accounts (real or demo) in one click,
/// so you don't need the command palette or Settings to tell them apart.
struct AccountSwitcher: View {
    @Environment(AccountStore.self) private var store

    var body: some View {
        Menu {
            ForEach(store.accounts) { account in
                Button {
                    store.currentAccountID = account.id
                } label: {
                    // A checkmark marks the current account; SwiftUI hides the leading space
                    // for the others so the labels stay aligned.
                    if account.id == store.currentAccountID {
                        Label(account.label, systemImage: "checkmark")
                    } else {
                        Text(account.label)
                    }
                }
            }

            if !store.accounts.isEmpty {
                Divider()
            }

            SettingsLink {
                Text("Manage Accounts…")
            }
        } label: {
            let icon = store.currentAccount == nil ? "person.crop.circle.badge.questionmark" : "person.crop.circle"
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(store.currentAccount?.label ?? "No account")
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityLabel("Current account: \(store.currentAccount?.label ?? "none")")
        .accessibilityHint("Switch accounts")
    }
}

#Preview("Two accounts") {
    let store = AccountStore.rankBuddy(
        isTesting: true,
        seed: [Account(label: "Work", token: "t"), .demo]
    )
    return AccountSwitcher()
        .environment(store)
        .frame(width: 220)
        .background(.bar)
        .padding()
}

#Preview("No account") {
    AccountSwitcher()
        .environment(AccountStore.rankBuddy(isTesting: true))
        .frame(width: 220)
}
