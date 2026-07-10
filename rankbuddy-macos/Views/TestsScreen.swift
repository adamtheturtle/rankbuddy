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
                    SortOption("Name") { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                    SortOption("Newest") { ($0.createdAt ?? "") > ($1.createdAt ?? "") },
                    SortOption("Start Time") { ($0.startTime ?? "") > ($1.startTime ?? "") }
                ],
                facets: [
                    ListFacet("library", "Library", systemImage: "books.vertical") { $0.libraryFilterValues },
                    ListFacet("role", "Role", systemImage: "person.text.rectangle") { $0.roleFilterValues },
                    ListFacet("skill", "Skill", systemImage: "target") { $0.skillFilterValues },
                    ListFacet("type", "Type", systemImage: "square.grid.2x2") { $0.typeFilterValues },
                    ListFacet("state", "State", systemImage: "circle.fill", value: { $0.state?.capitalized }),
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
                        openInWindow: { openWindow(value: DetailWindowValue.test(test)) }
                    )
                },
                onFirstPage: { tests in
                    RecentActivityStore.shared.record(
                        tests.map {
                            RecentItem(collection: .tests, id: $0.id, title: $0.name, subtitle: $0.state?.capitalized)
                        },
                        for: .tests,
                        account: account.id
                    )
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
                    RowTransfer(title: test.name, subtitle: test.state?.capitalized, fields: [
                        ("Name", test.name),
                        ("State", test.state?.capitalized ?? ""),
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
    private func loadMergedTests(_: String?) async throws -> Page<AccountScoped<Test>> {
        let items = try await MergedLoader.firstPages(accounts: store.accounts) {
            try await HackerRankClient(account: $0).testsPage().items
        }
        return Page(items: items, next: nil)
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
                SortOption("Name") { $0.item.name.localizedStandardCompare($1.item.name) == .orderedAscending },
                SortOption("Account", by: AccountScoped.byAccountLabel),
                SortOption("Newest") { ($0.item.createdAt ?? "") > ($1.item.createdAt ?? "") }
            ],
            facets: [
                ListFacet("account", "Account", systemImage: "person.crop.circle", value: { $0.account.label }),
                ListFacet("library", "Library", systemImage: "books.vertical") { $0.item.libraryFilterValues },
                ListFacet("role", "Role", systemImage: "person.text.rectangle") { $0.item.roleFilterValues },
                ListFacet("skill", "Skill", systemImage: "target") { $0.item.skillFilterValues },
                ListFacet("type", "Type", systemImage: "square.grid.2x2") { $0.item.typeFilterValues },
                ListFacet("state", "State", systemImage: "circle.fill", value: { $0.item.state?.capitalized })
            ],
            contextMenu: { rowMenuItems(copyLabel: "Copy Name", copyText: $0.item.name) },
            rowTransfer: { scoped in
                RowTransfer(title: scoped.item.name, subtitle: scoped.account.label, fields: [
                    ("Name", scoped.item.name),
                    ("Account", scoped.account.label),
                    ("State", scoped.item.state?.capitalized ?? ""),
                    ("Unique ID", scoped.item.uniqueID ?? "")
                ])
            },
            rowDate: { DisplayFormat.parseDate($0.item.startTime) },
            row: {
                MergedRow(title: $0.item.name, subtitle: $0.item.state?.capitalized, account: $0.account)
            },
            detail: { TestDetailView(test: $0.item, account: $0.account) }
        )
    }
}

/// One row in the tests list.
struct TestRow: View {
    let test: Test

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(test.name).listRowTitleStyle()
                HStack(spacing: 8) {
                    if let state = test.state {
                        Text(state.capitalized)
                    }
                }
                .listRowMetadataStyle()
            }
            .listRowTextColumn()
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                test.windowBadge(now: Date())
                if test.enableProctoring == true {
                    StatusBadge(text: "Proctored", systemImage: "eye.fill", tint: .blue)
                }
            }
        }
        .accessibilityElement(children: .combine)
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
