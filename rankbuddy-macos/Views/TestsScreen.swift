import BuddyAppKit
import SwiftUI

/// The Tests section: a list of the account's tests, each opening a read-only detail
/// view that also links to the test's candidates.
struct TestsScreen: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.hackerRankSession) private var session

    var body: some View {
        NavigationStack {
            if let account = store.currentAccount {
                LoadableList(
                    title: "Tests",
                    emptyMessage: "No tests",
                    load: { try await HackerRankClient(account: account, session: session).tests() },
                    searchableText: { "\($0.name) \($0.tags?.joined(separator: " ") ?? "")" },
                    row: { TestRow(test: $0) },
                    detail: { TestDetailView(test: $0, account: account) }
                )
            } else {
                NoAccountView()
                    .navigationTitle("Tests")
            }
        }
    }
}

/// One row in the tests list.
struct TestRow: View {
    let test: Test

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
            if test.enableProctoring == true {
                StatusBadge(text: "Proctored", systemImage: "eye.fill", tint: .blue)
            }
        }
        .rowContextMenu(copyLabel: "Copy Name", copyText: test.name)
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
                OptionalRow("Unique ID", test.uniqueID)
                OptionalRow("Duration", test.duration.map { "\($0) min" })
                OptionalRow("Cutoff score", test.cutoffScore.map(String.init))
                OptionalRow("Starts", DisplayFormat.date(test.startTime))
                OptionalRow("Ends", DisplayFormat.date(test.endTime))
                OptionalRow("Created", DisplayFormat.date(test.createdAt))
                OptionalRow("Languages", DisplayFormat.list(test.languages))
                OptionalRow("Tags", DisplayFormat.list(test.tags))
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
                    Text(instructions).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(test.name)
    }
}
