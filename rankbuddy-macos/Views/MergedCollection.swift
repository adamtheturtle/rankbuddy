//
//  MergedCollection.swift
//  rankbuddy-macos
//

import BuddyDesignSystem
import Foundation
import HackerRankKit
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
nonisolated extension AccountScoped: Codable where Item: Codable {}

/// One account omitted from a merged collection load.
nonisolated struct MergedAccountFailure: Equatable {
    let account: Account
    let message: String
}

/// Carries usable rows and the accounts that could not be loaded through `LoadableList`'s
/// throwing page boundary. `LoadableList` recognizes this error, keeps the page visible, and
/// presents a retryable warning instead of making a partial collection look complete.
nonisolated struct PartialMergedPage<Item: Identifiable & Hashable & Sendable>: Error {
    let page: Page<Item>
    let failures: [MergedAccountFailure]

    var warning: String {
        let labels = failures.map(\.account.label).formatted()
        let noun = failures.count == 1 ? "account" : "accounts"
        return "Couldn’t load \(labels). Rows from \(noun) may be missing."
    }
}

/// Loads the first page of a collection from several accounts and merges the results (#17).
enum MergedLoader {
    private nonisolated struct Cursor: Codable {
        let byAccountID: [String: String]
    }

    /// Loads one page from every account that still has data, encoding the independent backend
    /// cursors into one opaque cursor that `LoadableList` can pass back on its next request.
    nonisolated static func page<Item: Identifiable & Hashable & Sendable>(
        accounts: [Account],
        cursor: String?,
        fetch: @escaping @Sendable (Account, String?) async throws -> Page<Item>
    ) async throws -> Page<AccountScoped<Item>> {
        let saved = try decodedCursor(cursor)
        let active = accounts.enumerated().filter { _, account in
            cursor == nil || saved[account.id.uuidString] != nil
        }
        guard !active.isEmpty else { return Page(items: [], next: nil) }

        let results = await withTaskGroup(
            of: (Int, Account, Result<Page<Item>, any Error>).self,
            returning: [(Int, Account, Result<Page<Item>, any Error>)].self
        ) { group in
            for (index, account) in active {
                group.addTask {
                    do {
                        return try await (index, account, .success(fetch(account, saved[account.id.uuidString])))
                    } catch {
                        return (index, account, .failure(error))
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        var items: [AccountScoped<Item>] = []
        var nextByAccount: [String: String] = [:]
        var firstError: (any Error)?
        var failures: [MergedAccountFailure] = []
        var anySuccess = false
        for (_, account, result) in results.sorted(by: { $0.0 < $1.0 }) {
            switch result {
            case let .success(page):
                anySuccess = true
                items += page.items.map { AccountScoped(account: account, item: $0) }
                if let next = page.next {
                    nextByAccount[account.id.uuidString] = next
                }

            case let .failure(error):
                firstError = firstError ?? error
                failures.append(MergedAccountFailure(account: account, message: error.localizedDescription))
                // Keep this account active at the same cursor so an explicit retry does not
                // silently abandon its remaining rows.
                if let previous = saved[account.id.uuidString] {
                    nextByAccount[account.id.uuidString] = previous
                }
            }
        }
        if !anySuccess, let firstError {
            throw firstError
        }

        let page = try Page(items: items, next: encodedCursor(nextByAccount))
        if !failures.isEmpty {
            throw PartialMergedPage<AccountScoped<Item>>(page: page, failures: failures)
        }
        return page
    }

    private nonisolated static func decodedCursor(_ value: String?) throws -> [String: String] {
        guard let value, let data = Data(base64Encoded: value) else { return [:] }

        return try JSONDecoder().decode(Cursor.self, from: data).byAccountID
    }

    private nonisolated static func encodedCursor(_ values: [String: String]) throws -> String? {
        guard !values.isEmpty else { return nil }

        return try JSONEncoder().encode(Cursor(byAccountID: values)).base64EncodedString()
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
                Text(title).listRowTitleStyle(fullText: title)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .listRowMetadataStyle()
                }
            }
            .listRowTextColumn()
            Spacer(minLength: 12)
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
            .layoutPriority(1)
        }
    }
}
