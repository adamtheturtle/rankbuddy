import SwiftUI

/// The candidates for a test, pushed from `TestDetailView`. Read-only list + detail.
struct CandidatesList: View {
    let testID: String
    let account: Account

    var body: some View {
        LoadableList(
            title: "Candidates",
            emptyMessage: "No candidates",
            loadPage: {
                try await HackerRankClient(account: account)
                    .candidatesPage(testID: testID, after: $0)
            },
            searchableText: { "\($0.fullName ?? "") \($0.email) \($0.listStatusLabel ?? "")" },
            sortOptions: [
                SortOption("Score") {
                    ($0.score ?? -.greatestFiniteMagnitude) > ($1.score ?? -.greatestFiniteMagnitude)
                },
                SortOption("Name") {
                    ($0.fullName ?? $0.email).localizedStandardCompare($1.fullName ?? $1.email) == .orderedAscending
                },
                SortOption("Recent") { ($0.attemptEndTime ?? "") > ($1.attemptEndTime ?? "") },
                // Higher ATS codes are further along the pipeline; unset/unknown sort last.
                SortOption("Status") { ($0.atsState ?? -1) > ($1.atsState ?? -1) }
            ],
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
                if let status = candidate.listStatusLabel {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            candidate.integrityBadge
        }
        .accessibilityElement(children: .combine)
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
                OptionalRow("Attempt", candidate.attemptStatusLabel)
                OptionalRow("Pipeline", candidate.pipelineStatusLabel)
                OptionalRow("Score", candidate.score.map { $0.formatted() })
                OptionalRow("Percentage", candidate.percentageScore.map { "\($0.formatted())%" })
                OptionalRow("Integrity", candidate.integrityStatus)
                OptionalRow("Plagiarism", candidate.plagiarismStatus.map { $0 ? "Flagged" : "Clear" })
                OptionalRow("Started", DisplayFormat.date(candidate.attemptStartTime))
                OptionalRow("Ended", DisplayFormat.date(candidate.attemptEndTime))
                OptionalRow(
                    "Time taken",
                    DisplayFormat.duration(fromISO: candidate.attemptStartTime, toISO: candidate.attemptEndTime)
                )

                if let report = candidate.reportURL, let url = URL(string: report) {
                    Link(destination: url) {
                        Label("Open report", systemImage: "doc.text")
                    }
                }

                if let pdf = candidate.pdfURL, let url = URL(string: pdf) {
                    Link(destination: url) {
                        Label("Download PDF report", systemImage: "arrow.down.doc")
                    }
                }
            }

            if candidate.hasProctoringSignals {
                Section("Proctoring") {
                    OptionalRow("Left test window", candidate.outOfWindowEvents.map { "\($0)×" })
                    OptionalRow("Time outside window", DisplayFormat.interval(candidate.outOfWindowDuration))
                    OptionalRow("Editor pastes", candidate.editorPasteCount.map { "\($0)×" })
                }
            }

            if let tags = candidate.tags, !tags.isEmpty {
                Section("Tags") {
                    TagList(tags: tags)
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

#Preview {
    let json = #"""
    [
      {"id":"c1","email":"ada@example.com","full_name":"Ada Lovelace","score":92.0,
       "status":7,"ats_state":21,"integrity_status":"clean"},
      {"id":"c2","email":"alan@example.com","full_name":"Alan Turing","score":81.5,"status":0},
      {"id":"c3","email":"grace@example.com","full_name":"Grace Hopper","score":58.0,
       "status":7,"ats_state":22,"plagiarism_status":true},
      {"id":"c4","email":"noname@example.com"}
    ]
    """#
    let candidates = (try? JSONDecoder().decode([TestCandidate].self, from: Data(json.utf8))) ?? []
    return VStack(alignment: .leading, spacing: 12) {
        ForEach(candidates) { candidate in
            CandidateRow(candidate: candidate)
            Divider()
        }
    }
    .padding()
    .frame(width: 360)
}

#Preview("Detail") {
    let json = #"""
    {"id":"c3","email":"grace@example.com","full_name":"Grace Hopper","score":58.0,
     "percentage_score":58.0,"integrity_status":"review","plagiarism_status":true,
     "status":7,"ats_state":22,"out_of_window_events":4,"out_of_window_duration":95.0,
     "editor_paste_count":7,"attempt_starttime":"2026-05-04T08:30:00Z",
     "attempt_endtime":"2026-05-04T09:20:00Z"}
    """#
    let candidate = try? JSONDecoder().decode(TestCandidate.self, from: Data(json.utf8))
    return NavigationStack {
        if let candidate {
            CandidateDetailView(candidate: candidate)
        }
    }
}
