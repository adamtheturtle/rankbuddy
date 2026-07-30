//
//  TestsScreen.swift
//  rankbuddy-macos
//

import BuddyAppKit
import HackerRankKit
import SwiftUI

/// The Tests section: a list of the account's tests, each opening a read-only detail
/// view that also links to the test's candidates. A "New Test" action and edit/delete
/// affordances are available (#57).
struct TestsScreen: View {
    @Environment(AccountStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.openWindow) private var openWindow
    @Environment(\.undoManager) private var undoManager
    @State private var createPresented = false
    @State private var reloadToken = 0

    var body: some View {
        if store.isMergedView {
            mergedList
        } else if let account = store.currentAccount {
            LoadableList(
                title: "Tests",
                emptyMessage: "No tests",
                loadPage: { try await HackerRankClient(account: account).testsPage(after: $0) },
                searchableText: { "\($0.name) \($0.tags?.joined(separator: " ") ?? "") \($0.metadataSearchText)" },
                sortOptions: [
                    SortOption("Name", systemImage: "textformat", kind: .text) {
                        $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    },
                    SortOption("Date Created", systemImage: "calendar", kind: .date,
                               isMissing: { DisplayFormat.parseDate($0.createdAt) == nil }, by: {
                                   guard
                                       let lhs = DisplayFormat.parseDate($0.createdAt),
                                       let rhs = DisplayFormat.parseDate($1.createdAt)
                                   else { return false }

                                   return lhs > rhs
                               }),
                    SortOption("Start Time", systemImage: "clock", kind: .date,
                               isMissing: { DisplayFormat.parseDate($0.startTime) == nil }, by: {
                                   guard
                                       let lhs = DisplayFormat.parseDate($0.startTime),
                                       let rhs = DisplayFormat.parseDate($1.startTime)
                                   else { return false }

                                   return lhs > rhs
                               })
                ],
                facets: [
                    ListFacet("library", "Library", systemImage: "books.vertical") { $0.libraryFilterValues },
                    ListFacet("role", "Role", systemImage: "person.text.rectangle") { $0.roleFilterValues },
                    ListFacet("skill", "Skill", systemImage: "target") { $0.skillFilterValues },
                    ListFacet("type", "Type", systemImage: "square.grid.2x2") { $0.typeFilterValues },
                    ListFacet(
                        "state",
                        "State",
                        systemImage: "circle.fill",
                        value: { DisplayFormat.enumLabel($0.state) }
                    ),
                    // Derived from the scheduling window (#55): lets a recruiter narrow to the
                    // tests candidates can still take (Open) vs. Upcoming/Closed.
                    ListFacet("window", "Window", systemImage: "clock", value: { $0.windowStatus(now: Date())?.label }),
                    ListFacet("language", "Language", systemImage: "chevron.left.forwardslash.chevron.right") {
                        ($0.languages ?? []).map(DisplayFormat.languageName)
                    }
                ],
                restorationKey: "selection.tests.\(account.id)",
                filterDate: { DisplayFormat.parseDate($0.startTime) },
                dateFilterLabel: "Starts",
                contextMenu: { test in
                    rowMenuItems(
                        copyLabel: "Copy Name",
                        copyText: test.name,
                        favorite: favorites.menuState(
                            accountID: store.currentAccountID,
                            collection: .tests,
                            itemID: test.id,
                            title: test.name,
                            undoManager: undoManager
                        ),
                        openInWindow: { openWindow(value: DetailWindowValue.test(test, accountID: account.id)) }
                    )
                },
                openInWindow: { openWindow(value: DetailWindowValue.test($0, accountID: account.id)) },
                onOpen: { test in
                    RecentActivityStore.shared.record(
                        [RecentItem(
                            collection: .tests,
                            id: test.id,
                            title: test.name,
                            subtitle: DisplayFormat.enumLabel(test.state),
                            startTime: test.startTime,
                            endTime: test.endTime
                        )],
                        for: .tests,
                        account: account.id
                    )
                },
                onItemsLoaded: { tests in
                    favorites.refreshMetadata(from: tests.map {
                        FavoriteRef(
                            accountID: account.id.uuidString,
                            collection: .tests,
                            itemID: $0.id,
                            title: $0.name
                        )
                    })
                },
                accessoryToolbar: { AnyView(createButton) },
                primaryMenuAction: AppCommandContext.Action(title: "New Test…") { createPresented = true },
                reloadToken: reloadToken,
                csvExport: { CSVExport.tests($0) },
                csvFilename: "tests",
                favoriteRef: { test in
                    store.currentAccountID.map {
                        FavoriteRef(accountID: $0.uuidString, collection: .tests, itemID: test.id, title: test.name)
                    }
                },
                rowTransfer: { test in
                    RowTransfer(title: test.name, subtitle: DisplayFormat.enumLabel(test.state), fields: [
                        ("Name", test.name),
                        ("State", DisplayFormat.enumLabel(test.state) ?? ""),
                        ("Unique ID", test.uniqueID ?? ""),
                        ("Starts", test.startTime ?? ""),
                        ("Ends", test.endTime ?? "")
                    ])
                },
                rowDate: { DisplayFormat.parseDate($0.startTime) },
                row: { TestRow(test: $0) },
                detail: { TestDetailView(test: $0, account: account, onChanged: { reloadToken += 1 }) }
            )
            .sheet(isPresented: $createPresented) {
                TestEditorSheet(account: account, mode: .create) { reloadToken += 1 }
            }
        } else {
            NavigationStack {
                NoAccountView()
                    .navigationTitle("Tests")
            }
        }
    }

    private var createButton: some View {
        Button {
            createPresented = true
        } label: {
            Label("New Test…", systemImage: "doc.badge.plus")
        }
        .help("Create a test")
    }

    /// Loads one merged page of tests across every configured account (#17).
    private func loadMergedTests(_ cursor: String?) async throws -> Page<AccountScoped<Test>> {
        try await MergedLoader.page(accounts: store.accounts, cursor: cursor) {
            try await HackerRankClient(account: $0).testsPage(after: $1)
        }
    }

    /// Tests merged across every configured account (#17). One page per account; rows carry an
    /// account badge and route their detail (and its Candidates drill-down) to the right account.
    private var mergedList: some View {
        LoadableList(
            title: "Tests",
            emptyMessage: "No tests",
            loadPage: loadMergedTests,
            searchableText: { "\($0.item.name) \($0.account.label) \($0.item.metadataSearchText)" },
            sortOptions: [
                SortOption("Name", systemImage: "textformat", kind: .text) {
                    $0.item.name.localizedStandardCompare($1.item.name) == .orderedAscending
                },
                SortOption("Account", systemImage: "person.crop.circle", kind: .text,
                           by: AccountScoped.byAccountLabel),
                SortOption("Date Created", systemImage: "calendar", kind: .date,
                           isMissing: { DisplayFormat.parseDate($0.item.createdAt) == nil }, by: {
                               guard
                                   let lhs = DisplayFormat.parseDate($0.item.createdAt),
                                   let rhs = DisplayFormat.parseDate($1.item.createdAt)
                               else { return false }

                               return lhs > rhs
                           })
            ],
            facets: [
                ListFacet("account", "Account", systemImage: "person.crop.circle", value: { $0.account.label }),
                ListFacet("library", "Library", systemImage: "books.vertical") { $0.item.libraryFilterValues },
                ListFacet("role", "Role", systemImage: "person.text.rectangle") { $0.item.roleFilterValues },
                ListFacet("skill", "Skill", systemImage: "target") { $0.item.skillFilterValues },
                ListFacet("type", "Type", systemImage: "square.grid.2x2") { $0.item.typeFilterValues },
                ListFacet(
                    "state",
                    "State",
                    systemImage: "circle.fill",
                    value: { DisplayFormat.enumLabel($0.item.state) }
                )
            ],
            contextMenu: { scoped in
                rowMenuItems(
                    copyLabel: "Copy Name",
                    copyText: scoped.item.name,
                    openInWindow: {
                        openWindow(value: DetailWindowValue.test(scoped.item, accountID: scoped.account.id))
                    }
                )
            },
            openInWindow: { openWindow(value: DetailWindowValue.test($0.item, accountID: $0.account.id)) },
            rowTransfer: { scoped in
                RowTransfer(title: scoped.item.name, subtitle: scoped.account.label, fields: [
                    ("Name", scoped.item.name),
                    ("Account", scoped.account.label),
                    ("State", DisplayFormat.enumLabel(scoped.item.state) ?? ""),
                    ("Unique ID", scoped.item.uniqueID ?? "")
                ])
            },
            rowDate: { DisplayFormat.parseDate($0.item.startTime) },
            row: {
                MergedRow(title: $0.item.name, subtitle: DisplayFormat.enumLabel($0.item.state), account: $0.account)
            },
            detail: { TestDetailView(test: $0.item, account: $0.account) }
        )
    }
}

/// One row in the tests list.
struct TestRow: View {
    let test: Test

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(test.name).listRowTitleStyle(fullText: test.name)
                    HStack(spacing: 8) {
                        if let state = test.state {
                            Text(DisplayFormat.enumLabel(state))
                        }
                    }
                    .listRowMetadataStyle()
                }
                .listRowTextColumn()
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    test.windowBadge(now: context.date)
                    if test.enableProctoring == true {
                        StatusBadge(text: "Proctored", systemImage: "eye.fill", tint: .blue)
                    }
                }
            }
        }
    }
}

#Preview {
    // Windows are relative to mid-2026, so these classify stably: open, upcoming, closed.
    let json = #"""
    [
      {"id":"t1","name":"Backend Screen","state":"active","enable_proctoring":true,
       "start_time":"2026-01-01T09:00:00Z","end_time":"2026-12-31T09:00:00Z"},
      {"id":"t2","name":"Frontend Take-Home","state":"active",
       "start_time":"2026-12-01T09:00:00Z"},
      {"id":"t3","name":"Data Structures Quiz","state":"archived",
       "end_time":"2026-02-01T09:00:00Z"}
    ]
    """#
    let tests = (try? JSONDecoder().decode([Test].self, from: Data(json.utf8))) ?? []
    // Favourite the first test so the row's star indicator is exercised in the preview (#25).
    let account = Account(label: "Demo", token: "demo")
    let favorites = FavoritesStore(isTesting: true)
    if let first = tests.first {
        favorites.toggle(FavoriteRef(
            accountID: account.id.uuidString,
            collection: .tests,
            itemID: first.id,
            title: first.name
        ))
    }
    return VStack(alignment: .leading, spacing: 12) {
        ForEach(tests) { test in
            TestRow(test: test)
            Divider()
        }
    }
    .padding()
    .frame(width: 420)
    .environment(AccountStore.rankBuddy(isTesting: true, seed: [account]))
    .environment(favorites)
}
