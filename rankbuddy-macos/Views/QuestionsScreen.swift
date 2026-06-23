import BuddyAppKit
import SwiftUI

/// The Questions section: a list of the account's questions with read-only detail.
struct QuestionsScreen: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.hackerRankSession) private var session

    var body: some View {
        NavigationStack {
            if let account = store.currentAccount {
                LoadableList(
                    title: "Questions",
                    emptyMessage: "No questions",
                    load: { try await HackerRankClient(account: account, session: session).questions() },
                    searchableText: { "\($0.name) \($0.type) \($0.tags?.joined(separator: " ") ?? "")" },
                    row: { QuestionRow(question: $0) },
                    detail: { QuestionDetailView(question: $0) }
                )
            } else {
                NoAccountView()
                    .navigationTitle("Questions")
            }
        }
    }
}

/// One row in the questions list.
struct QuestionRow: View {
    let question: Question

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(question.name).font(.headline)
            HStack(spacing: 8) {
                Text(question.type.capitalized)
                if let languages = DisplayFormat.list(question.languages) {
                    Text(languages)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// Read-only detail for a single question.
struct QuestionDetailView: View {
    let question: Question

    var body: some View {
        Form {
            Section("Question") {
                OptionalRow("Name", question.name)
                OptionalRow("Type", question.type.capitalized)
                OptionalRow("Unique ID", question.uniqueID)
                OptionalRow("Status", question.status?.capitalized)
                OptionalRow("Max score", question.maxScore.map { $0.formatted() })
                OptionalRow("Recommended duration", question.recommendedDuration.map { "\($0) min" })
                OptionalRow("Created", DisplayFormat.date(question.createdAt))
                OptionalRow("Languages", DisplayFormat.list(question.languages))
                OptionalRow("Tags", DisplayFormat.list(question.tags))
            }

            if let statement = question.problemStatement, !statement.isEmpty {
                Section("Problem statement") {
                    Text(statement).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(question.name)
    }
}
