//
//  NoAccountView.swift
//  rankbuddy-macos
//

import BuddyAppKit
import SwiftUI

/// Shown when a section needs an account but none is configured. On first run (no accounts
/// at all) it's a small onboarding surface explaining what RankBuddy needs, with a one-click
/// demo so the app can be explored before connecting a real token.
struct NoAccountView: View {
    @Environment(AccountStore.self) private var store
    @State private var recovery = AccountDataRecovery.shared

    var body: some View {
        if let issue = recovery.issue {
            ContentUnavailableView {
                Label("Saved Accounts Need Recovery", systemImage: "key.viewfinder")
            } description: {
                if issue.replacementAllowed {
                    Text("RankBuddy couldn't read the saved account data. The original Keychain " +
                        "payload has been backed up, so you can safely add accounts again. " +
                        "The saved tokens have not been discarded.")
                } else {
                    Text("RankBuddy couldn't read the saved account data or create a Keychain " +
                        "backup. Account changes are blocked to protect the original payload.")
                }
            } actions: {
                SettingsLink {
                    Text("Open Account Settings")
                }
                .buttonStyle(.borderedProminent)
            }
        } else if store.accounts.isEmpty {
            ContentUnavailableView {
                Label("Welcome to RankBuddy", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("RankBuddy connects to HackerRank for Work with a personal access token, " +
                    "then keeps your tests, candidates, questions, and interviews a click away. " +
                    "Add an account to get started, or explore the demo first.")
            } actions: {
                SettingsLink {
                    Text("Add Account…")
                }
                .buttonStyle(.borderedProminent)

                Button("Add Demo Account") { store.add(.demo) }

                GetTokenLink()
            }
        } else {
            ContentUnavailableView {
                Label("No account selected", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("Choose one of your saved accounts in Settings.")
            } actions: {
                SettingsLink {
                    Text("Open Settings")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
