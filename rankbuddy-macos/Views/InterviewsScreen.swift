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
                loadPage: { try await HackerRankClient(account: account, session: session).interviewsPage(after: $0) },
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

extension Interview {
    /// A tinted badge for the interview's lifecycle status. Always returns a badge — the
    /// status is required — falling back to a neutral pill with the raw (capitalised) value
    /// for any status not given a dedicated colour.
    var statusBadge: StatusBadge {
        switch status.lowercased() {
        case "completed":
            StatusBadge(text: "Completed", systemImage: "checkmark.circle.fill", tint: .green)
        case "scheduled":
            StatusBadge(text: "Scheduled", systemImage: "calendar", tint: .blue)
        case "in_progress", "in progress":
            StatusBadge(text: "In progress", systemImage: "clock", tint: .orange)
        case "cancelled", "canceled":
            StatusBadge(text: "Cancelled", systemImage: "xmark.circle", tint: .red)
        default:
            StatusBadge(text: status.capitalized, systemImage: "circle", tint: .secondary)
        }
    }
}

/// One row in the interviews list.
struct InterviewRow: View {
    let interview: Interview

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(interview.title ?? "Interview \(interview.id)").font(.headline)
                if let created = DisplayFormat.date(interview.createdAt) {
                    Text(created)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            interview.statusBadge
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

#Preview {
    let json = #"""
    [
      {"id":"i1","status":"completed","url":"https://example.com/i1",
       "title":"Senior Backend — Pairing","created_at":"2026-05-05T13:00:00Z"},
      {"id":"i2","status":"scheduled","url":"https://example.com/i2",
       "title":"Frontend — Live Coding","created_at":"2026-05-12T16:00:00Z"},
      {"id":"i3","status":"cancelled","url":"https://example.com/i3","title":"Platform — Screen"}
    ]
    """#
    let interviews = (try? JSONDecoder().decode([Interview].self, from: Data(json.utf8))) ?? []
    return VStack(alignment: .leading, spacing: 12) {
        ForEach(interviews) { interview in
            InterviewRow(interview: interview)
            Divider()
        }
    }
    .padding()
    .frame(width: 420)
}
