//
//  TemplatesScreen.swift
//  rankbuddy-macos
//

import BuddyAppKit
import HackerRankKit
import SwiftUI

struct TemplatesScreen: View {
    @Environment(AccountStore.self) private var store
    @AppStorage("templates.kind") private var kind: TemplateKind = .interview
    @AppStorage("templates.ownership") private var ownership: TemplateOwnership = .all
    @State private var creationAccount: Account?
    @State private var reloadToken = 0
    @State private var requestQuery: [URLQueryItem] = []

    var body: some View {
        Group {
            if store.isMergedView {
                mergedList
            } else if let account = store.currentAccount {
                accountList(account)
            } else {
                NavigationStack {
                    NoAccountView().navigationTitle("Templates")
                }
            }
        }
        // Rebuild loaders and details when scope, credentials or filters change.
        .id(Scope(accountVersions: (store.isMergedView ? store.accounts : store.currentAccount.map { [$0] } ?? [])
                .map(\.hashValue),
            kind: kind, ownership: ownership, merged: store.isMergedView))
        .nativeListFilters(kind == .interview ? "api_list_all_interview_templates" : "api_list_all_invite_templates",
                           title: kind == .interview ? "Interview Templates" : "Assessment Templates",
                           query: $requestQuery)
        .sheet(item: $creationAccount) { account in
            TemplateEditorSheet(account: account) {
                ownership = .owned
                reloadToken += 1
            }
        }
    }

    private struct Scope: Hashable {
        // Ephemeral fingerprints detect credential changes without putting tokens in view identities.
        let accountVersions: [Int]
        let kind: TemplateKind
        let ownership: TemplateOwnership
        let merged: Bool
    }

    private var controls: some View {
        HStack {
            if kind == .interview {
                if store.isMergedView {
                    Menu("New Template", systemImage: "plus") {
                        ForEach(store.accounts) { account in
                            Button(account.label) { beginCreation(account) }
                        }
                    }
                } else if let account = store.currentAccount {
                    Button("New Template", systemImage: "plus") { beginCreation(account) }
                        .help("Create an interview template")
                        .accessibilityIdentifier("new-template")
                }
            }
            Picker("Template Type", selection: $kind) {
                ForEach(TemplateKind.allCases) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("template-kind")
            .accessibilityLabel("Template Type")
            if kind == .interview {
                Picker("Ownership", selection: $ownership) {
                    ForEach(TemplateOwnership.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("template-ownership")
                .accessibilityLabel("Template Ownership")
            }
        }
        .pickerStyle(.menu)
    }

    private func accountList(_ account: Account) -> some View {
        LoadableList(
            title: kind.title,
            emptyMessage: "No templates",
            loadPage: {
                try await TemplateLibrary.page(client: HackerRankClient(account: account),
                                               kind: kind, ownership: ownership, cursor: $0, query: requestQuery)
            },
            searchableText: { $0.searchableText },
            sortOptions: [
                SortOption("Name", systemImage: "textformat", kind: .text) {
                    $0.title.localizedStandardCompare($1.title) == .orderedAscending
                },
                SortOption("Date Created", systemImage: "calendar", kind: .date,
                           isMissing: { DisplayFormat.parseDate($0.createdAt) == nil }, by: {
                               (DisplayFormat.parseDate($0.createdAt) ?? .distantPast)
                                   > (DisplayFormat.parseDate($1.createdAt) ?? .distantPast)
                           })
            ],
            restorationKey: requestQuery.isEmpty
                ? TemplateLibrary.cacheKey(accountID: account.id, kind: kind, ownership: ownership) : nil,
            contextMenu: { rowMenuItems(copyLabel: "Copy Name", copyText: $0.title) },
            accessoryToolbar: { AnyView(controls) },
            primaryMenuAction: kind == .interview ? .init(title: "New Template…", perform: {
                beginCreation(account)
            }) : nil,
            reloadToken: reloadToken,
            rowTransfer: {
                RowTransfer(title: $0.title, subtitle: $0.subtitle,
                            fields: [("Name", $0.title), ("ID", $0.apiID ?? "")])
            },
            rowDate: { DisplayFormat.parseDate($0.createdAt) },
            row: { TemplateRow(record: $0) },
            detail: { TemplateDetailView(record: $0, account: account, onChanged: { reloadToken += 1 }).id($0.id) }
        )
    }

    private var mergedList: some View {
        LoadableList(
            title: kind.title,
            emptyMessage: "No templates",
            loadPage: { cursor in
                let selectedKind = kind
                let selectedOwnership = ownership
                return try await MergedLoader.page(accounts: store.accounts, cursor: cursor) { account, next in
                    try await TemplateLibrary.page(client: HackerRankClient(account: account), kind: selectedKind,
                                                   ownership: selectedOwnership, cursor: next, query: requestQuery)
                }
            },
            searchableText: { "\($0.item.searchableText) \($0.account.label)" },
            sortOptions: [
                SortOption("Name", systemImage: "textformat", kind: .text) {
                    $0.item.title.localizedStandardCompare($1.item.title) == .orderedAscending
                },
                SortOption("Account", systemImage: "person.crop.circle", kind: .text, by: AccountScoped.byAccountLabel)
            ],
            contextMenu: { rowMenuItems(copyLabel: "Copy Name", copyText: $0.item.title) },
            accessoryToolbar: { AnyView(controls) },
            reloadToken: reloadToken,
            row: { MergedRow(title: $0.item.title, subtitle: $0.item.subtitle, account: $0.account) },
            detail: {
                TemplateDetailView(record: $0.item, account: $0.account, onChanged: { reloadToken += 1 }).id($0.id)
            }
        )
    }

    private func beginCreation(_ account: Account) {
        creationAccount = account
    }
}

private struct TemplateRow: View {
    let record: TemplateRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(record.title).lineLimit(1)
            if let subtitle = record.subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
