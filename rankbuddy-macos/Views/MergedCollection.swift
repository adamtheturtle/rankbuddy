//
//  MergedCollection.swift
//  rankbuddy-macos
//

import BuddyDesignSystem
import SwiftUI

/// An item paired with the account it came from, for the multi-account merged lists (#17).
/// Carries the source account on every row so navigation, detail, and context actions target
/// the right account.
nonisolated struct AccountScoped<Item: Identifiable & Hashable & Sendable>: Identifiable, Hashable {
    let account: Account
    let item: Item

    /// Unique across accounts: an item with the same id in two accounts stays distinct.
    var id: String {
        "\(account.id.uuidString)|\(item.id)"
    }

    /// Orders merged rows by their account label — the shared "Account" sort for merged lists.
    static func byAccountLabel(_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.account.label.localizedStandardCompare(rhs.account.label) == .orderedAscending
    }
}

/// `Codable` to satisfy `LoadableList`'s item bound (#102). Merged lists never persist a page —
/// they pass no restoration key — so this conformance only ever type-checks; it never writes an
/// account's token to disk.
extension AccountScoped: Codable where Item: Codable {}

/// Loads the first page of a collection from several accounts and merges the results (#17).
enum MergedLoader {
    /// Fetches each account's first page, tagging every item with its account. Accounts whose
    /// fetch fails are skipped so one failing account never discards the others' results
    /// (partial results); throws only when **every** account fails, so the list surfaces an
    /// error instead of a misleading empty state. No accounts → an empty list.
    @MainActor
    static func firstPages<Item>(
        accounts: [Account],
        fetch: @MainActor (Account) async throws -> [Item]
    ) async throws -> [AccountScoped<Item>] {
        var scoped: [AccountScoped<Item>] = []
        var firstError: Error?
        var anySuccess = false

        for account in accounts {
            do {
                let items = try await fetch(account)
                anySuccess = true
                scoped += items.map { AccountScoped(account: account, item: $0) }
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if !anySuccess, let firstError {
            throw firstError
        }
        return scoped
    }
}

/// A merged-list row: the item's title/subtitle plus a trailing chip naming its source account,
/// so rows from different accounts stay distinguishable (#17). The chip uses the account's own
/// avatar (its tint + chosen icon, or initials) rather than a generic person glyph — matching
/// PadBuddy and the avatar shown in the switcher and sidebar — so multi-account users can tell at
/// a glance which account a row belongs to.
struct MergedRow: View {
    let title: String
    var subtitle: String?
    let account: Account

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.medium))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                AvatarCircle(
                    label: account.label,
                    diameter: 16,
                    tint: account.tintColor ?? .accentColor,
                    symbol: account.displayIcon
                )
                Text(account.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
