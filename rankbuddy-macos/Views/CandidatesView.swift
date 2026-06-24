import SwiftUI

/// The candidates for a test, pushed from `TestDetailView`. Read-only list + detail.
struct CandidatesList: View {
    @Environment(\.hackerRankSession) private var session
    let testID: String
    let account: Account

    var body: some View {
        LoadableList(
            title: "Candidates",
            emptyMessage: "No candidates",
            load: { try await HackerRankClient(account: account, session: session).candidates(testID: testID) },
            searchableText: { "\($0.fullName ?? "") \($0.email)" },
            row: { CandidateRow(candidate: $0) },
            detail: { CandidateDetailView(candidate: $0) }
        )
    }
}

/// One row in the candidates list.
struct CandidateRow: View {
    let candidate: TestCandidate

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.fullName ?? candidate.email).font(.headline)
                HStack(spacing: 8) {
                    Text(candidate.email)
                    if let score = candidate.score {
                        Text("Score: \(score.formatted())")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            candidate.integrityBadge
        }
        .rowContextMenu(
            copyLabel: "Copy Email",
            copyText: candidate.email,
            link: candidate.reportURL,
            openLabel: "Open Report"
        )
    }
}

/// Read-only detail for a single candidate.
struct CandidateDetailView: View {
    let candidate: TestCandidate

    var body: some View {
        Form {
            Section("Candidate") {
                OptionalRow("Name", candidate.fullName)
                OptionalRow("Email", candidate.email)
                OptionalRow("Score", candidate.score.map { $0.formatted() })
                OptionalRow("Percentage", candidate.percentageScore.map { "\($0.formatted())%" })
                OptionalRow("Integrity", candidate.integrityStatus)
                OptionalRow("Plagiarism", candidate.plagiarismStatus.map { $0 ? "Flagged" : "Clear" })
                OptionalRow("Started", DisplayFormat.date(candidate.attemptStartTime))
                OptionalRow("Ended", DisplayFormat.date(candidate.attemptEndTime))
                OptionalRow("Tags", DisplayFormat.list(candidate.tags))

                if let report = candidate.reportURL, let url = URL(string: report) {
                    Link(destination: url) {
                        Label("Open report", systemImage: "doc.text")
                    }
                }
            }

            if let feedback = candidate.feedback, !feedback.isEmpty {
                Section("Feedback") {
                    Text(feedback).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(candidate.fullName ?? candidate.email)
    }
}
