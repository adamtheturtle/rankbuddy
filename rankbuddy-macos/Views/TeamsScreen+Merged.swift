//
//  TeamsScreen+Merged.swift
//  rankbuddy-macos
//

import BuddyAppKit
import HackerRankKit
import SwiftUI

extension TeamsScreen {
    /// Loads one page per account and retains the source account on every team.
    func loadMergedTeams(_: String?) async throws -> Page<AccountScoped<Team>> {
        let items = try await MergedLoader.firstPages(accounts: store.accounts) {
            try await HackerRankClient(account: $0).teamsPage().items
        }
        return Page(items: items, next: nil)
    }

    /// All-account teams are read and managed using the credential attached to each row.
    var mergedList: some View {
        LoadableList(
            title: "Teams",
            emptyMessage: "No teams",
            loadPage: loadMergedTeams,
            searchableText: {
                "\($0.item.name) \($0.item.departments?.joined(separator: " ") ?? "") \($0.account.label)"
            },
            sortOptions: [
                SortOption("Name", systemImage: "textformat", kind: .text) {
                    $0.item.name.localizedStandardCompare($1.item.name) == .orderedAscending
                },
                SortOption(
                    "Account",
                    systemImage: "person.crop.circle",
                    kind: .text,
                    by: AccountScoped.byAccountLabel
                ),
                SortOption("Size", systemImage: "person.3", kind: .amount) {
                    ($0.item.developerCount ?? 0) > ($1.item.developerCount ?? 0)
                }
            ],
            facets: [
                ListFacet("department", "Department", systemImage: "building.2") {
                    $0.item.departments ?? []
                },
                ListFacet("location", "Location", systemImage: "mappin.and.ellipse") {
                    $0.item.locations ?? []
                }
            ],
            contextMenu: { scoped in
                rowMenuItems(
                    copyLabel: "Copy Name",
                    copyText: scoped.item.name,
                    openInWindow: {
                        openWindow(value: DetailWindowValue.team(scoped.item, accountID: scoped.account.id))
                    }
                )
            },
            openInWindow: {
                openWindow(value: DetailWindowValue.team($0.item, accountID: $0.account.id))
            },
            rowTransfer: { scoped in
                RowTransfer(
                    title: scoped.item.name,
                    subtitle: scoped.account.label,
                    fields: scoped.item.transferFields + [("Account", scoped.account.label)]
                )
            },
            rowDate: { DisplayFormat.parseDate($0.item.createdAt) },
            row: {
                MergedRow(title: $0.item.name, subtitle: $0.item.memberSummary, account: $0.account)
            },
            detail: {
                TeamDetailView(team: $0.item, account: $0.account) { reloadToken += 1 }
            }
        )
    }
}
