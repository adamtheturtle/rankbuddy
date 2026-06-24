import BuddyAppKit
import SwiftUI

/// The Interviews section: a list of the account's interviews with read-only detail.
struct InterviewsScreen: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.hackerRankSession) private var session

    var body: some View {
        if let account = store.currentAccount {
            LoadableList(
                title: "Interviews",
                emptyMessage: "No interviews",
                load: { try await HackerRankClient(account: account, session: session).interviews() },
                searchableText: { "\($0.title ?? "") \($0.status)" },
                sortOptions: [
                    SortOption("Newest") { ($0.createdAt ?? "") > ($1.createdAt ?? "") },
                    SortOption("Status") { $0.status.localizedStandardCompare($1.status) == .orderedAscending },
                    SortOption("Title") {
                        ($0.title ?? "").localizedStandardCompare($1.title ?? "") == .orderedAscending
                    }
                ],
                restorationKey: "selection.interviews.\(account.id)",
                row: { InterviewRow(interview: $0) },
                detail: { InterviewDetailView(interview: $0) }
            )
        } else {
            NavigationStack {
                NoAccountView()
                    .navigationTitle("Interviews")
            }
        }
    }
}

/// One row in the interviews list.
struct InterviewRow: View {
    let interview: Interview

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(interview.title ?? "Interview \(interview.id)").font(.headline)
            HStack(spacing: 8) {
                Text(interview.status.capitalized)
                if let created = DisplayFormat.date(interview.createdAt) {
                    Text(created)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .rowContextMenu(
            copyLabel: "Copy Title",
            copyText: interview.title ?? "Interview \(interview.id)",
            link: interview.url
        )
    }
}

/// Read-only detail for a single interview.
struct InterviewDetailView: View {
    let interview: Interview

    var body: some View {
        Form {
            Section("Interview") {
                OptionalRow("Title", interview.title)
                OptionalRow("Status", interview.status.capitalized)
                OptionalRow("Created", DisplayFormat.date(interview.createdAt))
                OptionalRow("Updated", DisplayFormat.date(interview.updatedAt))
                OptionalRow("Ended", DisplayFormat.date(interview.endedAt))
                OptionalRow("Thumbs up", interview.thumbsUp.map(String.init))

                if let url = URL(string: interview.url) {
                    Link(destination: url) {
                        Label("Open in browser", systemImage: "safari")
                    }
                }
            }

            if let notes = interview.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes).textSelection(.enabled)
                }
            }

            if let feedback = interview.feedback, !feedback.isEmpty {
                Section("Feedback") {
                    Text(feedback).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(interview.title ?? "Interview")
    }
}
