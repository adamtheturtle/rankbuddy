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

    @State private var requestQuery: [URLQueryItem] = []

    var body: some View {
        screen.nativeListFilters("api_list_all_candidates", query: $requestQuery)
    }

    private var screen: some View {
        LoadableList(
            title: "Candidates",
            emptyMessage: "No candidates",
            loadPage: {
                try await NativeListQuery.page(TestCandidate.self, client: HackerRankClient(account: account),
                                               operationID: "api_list_all_candidates", path: ["test_id": testID],
                                               query: requestQuery, cursor: $0)
            },
            // The search field queries the server (#104), so a candidate deep in a long list is
            // reachable — not just one already paged into the loaded rows.
            serverSearch: { query, cursor in
                try await NativeListQuery.page(TestCandidate.self, client: HackerRankClient(account: account),
                                               operationID: "api_search_test_candidates", path: ["test_id": testID],
                                               query: requestQuery + [URLQueryItem(name: "search", value: query)],
                                               cursor: cursor)
            },
            searchableText: { "\($0.fullName ?? "") \($0.email) \($0.listStatusLabel ?? "")" },
            sortOptions: [
                SortOption("Score", systemImage: "chart.bar", kind: .amount,
                           isMissing: { $0.score == nil }, by: {
                               ($0.score ?? -.greatestFiniteMagnitude) > ($1.score ?? -.greatestFiniteMagnitude)
                           }),
                SortOption("Name", systemImage: "textformat", kind: .text) {
                    ($0.fullName ?? $0.email).localizedStandardCompare($1.fullName ?? $1.email) == .orderedAscending
                },
                SortOption("Attempted", systemImage: "clock", kind: .date,
                           isMissing: { DisplayFormat.parseDate($0.attemptEndTime) == nil }, by: {
                               guard
                                   let lhs = DisplayFormat.parseDate($0.attemptEndTime),
                                   let rhs = DisplayFormat.parseDate($1.attemptEndTime)
                               else { return false }

                               return lhs > rhs
                           }),
                // Higher ATS codes are further along the pipeline; unset/unknown sort last.
                SortOption("Status", systemImage: "circle.fill", kind: .amount,
                           isMissing: { $0.atsState == nil }, by: {
                               ($0.atsState ?? -1) > ($1.atsState ?? -1)
                           })
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
                    openInWindow: {
                        openWindow(value: DetailWindowValue.candidateWindow(
                            candidate,
                            testID: testID,
                            accountID: account.id
                        ))
                    }
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
            openInWindow: {
                openWindow(value: DetailWindowValue.candidateWindow(
                    $0,
                    testID: testID,
                    accountID: account.id
                ))
            },
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
        Binding(get: { value.wrappedValue != nil }, set: {
            if !$0 {
                value.wrappedValue = nil
            }
        })
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
