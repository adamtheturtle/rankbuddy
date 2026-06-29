//
//  TestsScreen.swift
//  rankbuddy-macos
//

import BuddyAppKit
import SwiftUI

/// The Tests section: a list of the account's tests, each opening a read-only detail
/// view that also links to the test's candidates. A "New Test" action and edit/delete
/// affordances are available (#57).
struct TestsScreen: View {
    @Environment(AccountStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.openWindow) private var openWindow
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
                searchableText: { "\($0.name) \($0.tags?.joined(separator: " ") ?? "")" },
                sortOptions: [
                    SortOption("Name") { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                    SortOption("Newest") { ($0.createdAt ?? "") > ($1.createdAt ?? "") },
                    SortOption("Start Time") { ($0.startTime ?? "") > ($1.startTime ?? "") }
                ],
                facets: [
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
                            title: test.name
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
                reloadToken: reloadToken,
                csvExport: { CSVExport.tests($0) },
                csvFilename: "tests",
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
            searchableText: { "\($0.item.name) \($0.account.label)" },
            sortOptions: [
                SortOption("Name") { $0.item.name.localizedStandardCompare($1.item.name) == .orderedAscending },
                SortOption("Account", by: AccountScoped.byAccountLabel),
                SortOption("Newest") { ($0.item.createdAt ?? "") > ($1.item.createdAt ?? "") }
            ],
            contextMenu: { rowMenuItems(copyLabel: "Copy Name", copyText: $0.item.name) },
            row: {
                MergedRow(title: $0.item.name, subtitle: $0.item.state?.capitalized, accountLabel: $0.account.label)
            },
            detail: { TestDetailView(test: $0.item, account: $0.account) }
        )
    }
}

/// One row in the tests list.
struct TestRow: View {
    let test: Test
    @Environment(AccountStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites

    private var favoriteRef: FavoriteRef? {
        store.currentAccountID.map {
            FavoriteRef(accountID: $0.uuidString, collection: .tests, itemID: test.id, title: test.name)
        }
    }

    private var isFavorite: Bool {
        guard let favoriteRef else { return false }

        return favorites.isFavorite(collection: .tests, accountID: favoriteRef.accountID, itemID: test.id)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(test.name).font(.headline)
                HStack(spacing: 8) {
                    if let state = test.state {
                        Text(state.capitalized)
                    }
                    if let start = DisplayFormat.date(test.startTime) {
                        Text(start)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                FavoriteIndicator(isFavorite: isFavorite)
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
