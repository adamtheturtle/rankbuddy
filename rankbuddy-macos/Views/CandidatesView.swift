//
//  CandidatesView.swift
//  rankbuddy-macos
//

import FastList
import HackerRankKit
import SwiftUI

/// The candidates for a test, opened in its own window from `TestDetailView`. Read-only list +
/// detail, with
/// an "Invite Candidate" write action (#12).
struct CandidatesList: View {
    let testID: String
    let account: Account

    @Environment(\.openWindow) private var openWindow
    @State private var invitePresented = false
    /// Bumped after a successful invite to refresh the list.
    @State private var reloadToken = 0
    @State private var candidatePendingInviteCancel: TestCandidate?
    @State private var candidatePendingReportDelete: TestCandidate?
    @State private var actionError: String?

    var body: some View {
        LoadableList(
            title: "Candidates",
            emptyMessage: "No candidates",
            loadPage: {
                try await HackerRankClient(account: account)
                    .candidatesPage(testID: testID, after: $0)
            },
            // The search field queries the server (#104), so a candidate deep in a long list is
            // reachable — not just one already paged into the loaded rows.
            serverSearch: { query, cursor in
                try await HackerRankClient(account: account)
                    .searchCandidates(testID: testID, query: query, after: cursor)
            },
            searchableText: { "\($0.fullName ?? "") \($0.email) \($0.listStatusLabel ?? "")" },
            sortOptions: [
                SortOption("Score", systemImage: "chart.bar", kind: .amount) {
                    ($0.score ?? -.greatestFiniteMagnitude) > ($1.score ?? -.greatestFiniteMagnitude)
                },
                SortOption("Name", systemImage: "textformat", kind: .text) {
                    ($0.fullName ?? $0.email).localizedStandardCompare($1.fullName ?? $1.email) == .orderedAscending
                },
                SortOption("Attempted", systemImage: "clock", kind: .date) {
                    ($0.attemptEndTime ?? "") > ($1.attemptEndTime ?? "")
                },
                // Higher ATS codes are further along the pipeline; unset/unknown sort last.
                SortOption("Status", systemImage: "circle.fill", kind: .amount) {
                    ($0.atsState ?? -1) > ($1.atsState ?? -1)
                }
            ],
            facets: [
                ListFacet("status", "Status", systemImage: "circle.fill", value: { $0.listStatusLabel })
            ],
            filterDate: { DisplayFormat.parseDate($0.attemptEndTime ?? $0.attemptStartTime) },
            dateFilterLabel: "Attempted",
            contextMenu: { candidate in
                var items = rowMenuItems(
                    copyLabel: "Copy Email",
                    copyText: candidate.email,
                    link: candidate.reportURL,
                    openLabel: "Open Report",
                    openInWindow: { openWindow(value: DetailWindowValue.candidate(candidate)) }
                )
                items.append(.separator)
                items.append(.button(title: "Cancel Invitation…") {
                    candidatePendingInviteCancel = candidate
                })
                items.append(.button(title: "Delete Report…") {
                    candidatePendingReportDelete = candidate
                })
                return items
            },
            openInWindow: { openWindow(value: DetailWindowValue.candidate($0)) },
            accessoryToolbar: { AnyView(inviteButton) },
            primaryMenuAction: AppCommandContext.Action(title: "Invite Candidate…") { invitePresented = true },
            reloadToken: reloadToken,
            csvExport: { CSVExport.candidates($0) },
            csvFilename: "candidates",
            rowTransfer: { candidate in
                RowTransfer(
                    title: candidate.fullName ?? candidate.email,
                    subtitle: candidate.email,
                    url: candidate.reportURL.flatMap(URL.remoteWebURL(from:)),
                    fields: [
                        ("Name", candidate.fullName ?? ""),
                        ("Email", candidate.email),
                        ("Score", candidate.score.map { String($0) } ?? ""),
                        ("Status", candidate.listStatusLabel ?? ""),
                        ("Report", candidate.reportURL ?? "")
                    ]
                )
            },
            rowDate: { DisplayFormat.parseDate($0.attemptEndTime ?? $0.attemptStartTime) },
            row: { CandidateRow(candidate: $0) },
            detail: { CandidateDetailView(candidate: $0, testID: testID, account: account) { reloadToken += 1 } }
        )
        .sheet(isPresented: $invitePresented) {
            InviteCandidateSheet(testID: testID, account: account) { reloadToken += 1 }
        }
        .confirmationDialog(
            "Cancel this invitation?",
            isPresented: presented($candidatePendingInviteCancel),
            titleVisibility: .visible,
            presenting: candidatePendingInviteCancel
        ) { candidate in
            Button("Cancel Invitation", role: .destructive) {
                Task { await cancelInvite(candidate) }
            }
            Button("Keep Invitation", role: .cancel) {}
        } message: { candidate in
            Text("This withdraws \(candidate.fullName ?? candidate.email)'s outstanding invite to the test.")
        }
        .confirmationDialog(
            "Delete this report?",
            isPresented: presented($candidatePendingReportDelete),
            titleVisibility: .visible,
            presenting: candidatePendingReportDelete
        ) { candidate in
            Button("Delete Report", role: .destructive) {
                Task { await deleteReport(candidate) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { candidate in
            Text("This permanently deletes \(candidate.fullName ?? candidate.email)'s test report "
                + "on HackerRank. This can’t be undone.")
        }
        .alert("Couldn’t complete that action", isPresented: presented($actionError)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var inviteButton: some View {
        Button {
            invitePresented = true
        } label: {
            Label("Invite Candidate…", systemImage: "person.badge.plus")
        }
        .help("Invite a candidate to this test")
    }

    /// A presented-flag for optional "pending action" state: dismissing clears it.
    private func presented(_ value: Binding<(some Any)?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }

    private func cancelInvite(_ candidate: TestCandidate) async {
        do {
            _ = try await HackerRankClient(account: account)
                .cancelCandidateInvite(testID: testID, candidateID: candidate.id)
            reloadToken += 1
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func deleteReport(_ candidate: TestCandidate) async {
        do {
            _ = try await HackerRankClient(account: account)
                .deleteCandidateReport(testID: testID, candidateID: candidate.id)
            reloadToken += 1
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// One row in the candidates list.
struct CandidateRow: View {
    let candidate: TestCandidate

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                let title = candidate.fullName ?? candidate.email
                Text(title).listRowTitleStyle(fullText: title)
                HStack(spacing: 8) {
                    Text(candidate.email)
                    if let score = candidate.score {
                        Text("Score: \(score.formatted())")
                    }
                }
                .listRowMetadataStyle()
                if let status = candidate.listStatusLabel {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .listRowTextColumn()
            Spacer(minLength: 12)
            candidate.integrityBadge
        }
    }

    private var subtitle: String {
        if let score = candidate.score {
            return "\(candidate.email) - Score: \(score.formatted())"
        }

        return candidate.email
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
