import BuddyAppKit
import SwiftUI

/// The Tests section: a list of the account's tests, each opening a read-only detail
/// view that also links to the test's candidates.
struct TestsScreen: View {
    @Environment(AccountStore.self) private var store

    var body: some View {
        if let account = store.currentAccount {
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
                restorationKey: "selection.tests.\(account.id)",
                row: { TestRow(test: $0) },
                detail: { TestDetailView(test: $0, account: account) }
            )
        } else {
            NavigationStack {
                NoAccountView()
                    .navigationTitle("Tests")
            }
        }
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
        .rowContextMenu(
            copyLabel: "Copy Name",
            copyText: test.name,
            isFavorite: favoriteRef != nil ? isFavorite : nil,
            toggleFavorite: favoriteRef.map { ref in { favorites.toggle(ref) } }
        )
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

#Preview("Detail") {
    let json = #"""
    {"id":"t1","unique_id":"backend-screen","name":"Backend Engineer Screen","state":"active",
     "duration":90,"cutoff_score":70,"enable_proctoring":true,"languages":["python","go"],
     "shuffle_questions":true,"starred":true,
     "start_time":"2026-01-01T09:00:00Z","end_time":"2026-12-31T09:00:00Z","questions":["q1","q2"],
     "tags":["backend"],
     "sections":[{"uuid":"s1","name":"Coding","questions":2,"duration":60},
                 {"uuid":"s2","name":"Multiple Choice","questions":5,"duration":30}]}
    """#
    let test = try? JSONDecoder().decode(Test.self, from: Data(json.utf8))
    return NavigationStack {
        if let test {
            TestDetailView(test: test, account: Account(label: "Demo", token: "demo"))
        }
    }
}

/// Read-only detail for a single test.
struct TestDetailView: View {
    let test: Test
    let account: Account

    var body: some View {
        Form {
            Section("Test") {
                OptionalRow("Name", test.name)
                OptionalRow("State", test.state?.capitalized)
                OptionalRow("Window", test.windowStatus(now: Date())?.label)
                OptionalRow("Unique ID", test.uniqueID)
                OptionalRow("Duration", test.duration.map { "\($0) min" })
                OptionalRow("Cutoff score", test.cutoffScore.map(String.init))
                OptionalRow("Questions", test.questions.map { "\($0.count)" })
                OptionalRow("Starts", DisplayFormat.date(test.startTime))
                OptionalRow("Ends", DisplayFormat.date(test.endTime))
                OptionalRow("Created", DisplayFormat.date(test.createdAt))
                OptionalRow("Languages", DisplayFormat.list(test.languages))
                OptionalRow("Proctoring", test.enableProctoring == true ? "Enabled" : nil)
                OptionalRow("Shuffle questions", test.shuffleQuestions == true ? "Yes" : nil)
                OptionalRow("Starred", test.starred == true ? "Yes" : nil)
                OptionalRow("Locked", test.locked == true ? "Yes" : nil)
                OptionalRow("Draft", test.draft == true ? "Yes" : nil)
            }

            if let sections = test.sections, !sections.isEmpty {
                Section("Sections") {
                    ForEach(sections) { section in
                        LabeledContent(section.displayName) {
                            if let count = section.questionCount {
                                Text("\(count) question\(count == 1 ? "" : "s")")
                            }
                        }
                    }
                }
            }

            if let tags = test.tags, !tags.isEmpty {
                Section("Tags") {
                    TagList(tags: tags)
                }
            }

            Section {
                NavigationLink {
                    CandidatesList(testID: test.id, account: account)
                } label: {
                    Label("Candidates", systemImage: "person.2")
                }
            }

            if let instructions = test.instructions, !instructions.isEmpty {
                Section("Instructions") {
                    HTMLText(html: instructions)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(test.name)
    }
}
