//
//  AccountSwitcher.swift
//  rankbuddy-macos
//

import AppKit
import BuddyAppKit
import BuddyDesignSystem
import SwiftUI

/// A compact account picker pinned to the bottom of the sidebar: it shows which account's
/// data is on screen and switches between configured accounts (real or demo) in one click,
/// so you don't need the command palette or Settings to tell them apart.
struct AccountSwitcher: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsTab.defaultsKey) private var selectedSettingsTab: SettingsTab = .general
    @ScaledMetric(relativeTo: .largeTitle) private var mergedIconSize: CGFloat = 28

    var body: some View {
        HStack(spacing: 10) {
            accountMenu
            Spacer(minLength: 0)
        }
    }

    /// The whole account identity is the menu trigger, and account choices are top-level items,
    /// matching PadBuddy's footer switcher.
    private var accountMenu: some View {
        Menu {
            if store.accounts.count > 1 {
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
            }

            ForEach(store.accounts) { account in
                Button {
                    store.selectAccount(account.id)
                } label: {
                    accountMenuLabel(for: account)
                }
            }

            if !store.accounts.isEmpty {
                Divider()
            }

            Button("Manage Accounts…") { manageAccounts() }
        } label: {
            triggerLabel
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Switch account")
        .accessibilityHint("Switch accounts")
    }

    @ViewBuilder
    private func accountMenuLabel(for account: Account) -> some View {
        if !store.isMergedView, account.id == store.currentAccount?.id {
            Label(account.label, systemImage: "checkmark")
        } else {
            Label(account.label, systemImage: account.displayIcon)
        }
    }

    private var triggerLabel: some View {
        let isMerged = store.isMergedView
        let title = isMerged ? "All Accounts" : (store.currentAccount?.label ?? "No Account")
        let subtitle = isMerged
            ? "\(store.accounts.count) accounts combined"
            : (store.accounts.count > 1 ? "Active · \(store.accounts.count) accounts" : "Active account")
        let accessibilityLabel = [title, subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        return HStack(spacing: 10) {
            if isMerged {
                Image(systemName: "person.2.circle.fill")
                    .font(.system(size: mergedIconSize))
                    .foregroundStyle(.purple)
            } else if let account = store.currentAccount {
                AvatarCircle(
                    label: account.label,
                    diameter: 30,
                    tint: account.tintColor ?? .accentColor,
                    symbol: account.displayIcon
                )
            } else {
                AvatarCircle(
                    label: "No Account",
                    diameter: 30,
                    tint: .secondary,
                    symbol: "person.crop.circle.badge.questionmark"
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .fixedSize(horizontal: true, vertical: true)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func manageAccounts() {
        selectedSettingsTab = .accounts
        openSettings()
    }
}

#Preview("Two accounts") {
    let store = AccountStore.rankBuddy(
        isTesting: true,
        seed: [Account(label: "Work", token: "t", iconSymbol: "briefcase", tintHex: "#8B5CF6"), .demo]
    )
    store.showAllAccounts = true
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
