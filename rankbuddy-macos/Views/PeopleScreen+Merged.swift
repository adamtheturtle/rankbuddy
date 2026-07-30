//
//  PeopleScreen+Merged.swift
//  rankbuddy-macos
//

import BuddyAppKit
import HackerRankKit
import SwiftUI

extension PeopleScreen {
    func loadMergedPeople(_: String?) async throws -> Page<AccountScoped<User>> {
        let items = try await MergedLoader.firstPages(accounts: store.accounts) {
            try await HackerRankClient(account: $0).usersPage().items
        }
        return Page(items: items, next: nil)
    }

    func searchMergedPeople(_ query: String, _: String?) async throws -> Page<AccountScoped<User>> {
        let items = try await MergedLoader.firstPages(accounts: store.accounts) {
            try await HackerRankClient(account: $0).searchUsers(query: query).items
        }
        return Page(items: items, next: nil)
    }

    var mergedList: some View {
        LoadableList(
            title: "People",
            emptyMessage: "No people",
            loadPage: loadMergedPeople,
            serverSearch: searchMergedPeople,
            searchableText: {
                "\($0.item.displayName) \($0.item.email) \($0.item.role ?? "") \($0.account.label)"
            },
            sortOptions: [
                SortOption("Name", systemImage: "textformat", kind: .text) {
                    $0.item.displayName.localizedStandardCompare($1.item.displayName) == .orderedAscending
                },
                SortOption(
                    "Account",
                    systemImage: "person.crop.circle",
                    kind: .text,
                    by: AccountScoped.byAccountLabel
                ),
                SortOption("Role", systemImage: "person.text.rectangle", kind: .text) {
                    ($0.item.role ?? "").localizedStandardCompare($1.item.role ?? "") == .orderedAscending
                }
            ],
            facets: [
                ListFacet("role", "Role", systemImage: "person.fill") {
                    DisplayFormat.enumLabel($0.item.role)
                },
                ListFacet("status", "Status", systemImage: "circle.fill") {
                    DisplayFormat.enumLabel($0.item.status)
                }
            ],
            contextMenu: { scoped in
                rowMenuItems(
                    copyLabel: "Copy Email",
                    copyText: scoped.item.email,
                    openInWindow: {
                        openWindow(value: DetailWindowValue.userWindow(
                            scoped.item,
                            accountID: scoped.account.id
                        ))
                    }
                )
            },
            openInWindow: {
                openWindow(value: DetailWindowValue.userWindow($0.item, accountID: $0.account.id))
            },
            rowTransfer: { scoped in
                RowTransfer(title: scoped.item.displayName, subtitle: scoped.account.label, fields: [
                    ("Name", scoped.item.displayName),
                    ("Email", scoped.item.email),
                    ("Account", scoped.account.label),
                    ("Role", DisplayFormat.enumLabel(scoped.item.role) ?? ""),
                    ("Status", DisplayFormat.enumLabel(scoped.item.status) ?? "")
                ])
            },
            rowDate: { DisplayFormat.parseDate($0.item.lastActivityTime) },
            row: {
                MergedRow(
                    title: $0.item.displayName,
                    subtitle: DisplayFormat.enumLabel($0.item.role),
                    account: $0.account
                )
            },
            detail: {
                PersonDetailView(user: $0.item, account: $0.account) { reloadToken += 1 }
            }
        )
    }
}
