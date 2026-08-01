//
//  CandidateDetailView.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

nonisolated enum CandidatePDFFetchGate {
    static func canStart(isFetching: Bool) -> Bool {
        !isFetching
    }
}

nonisolated struct CandidateDetailRequestIdentity: Hashable {
    let accountID: UUID?
    let testID: String?
    let candidateID: String
}

/// Detail for a single candidate. With a test and account the name renames in place and
/// the tags save per field via `updateCandidate` (#147); otherwise it stays read-only.
struct CandidateDetailView: View {
    let candidate: TestCandidate
    var testID: String?
    var account: Account?
    var onChanged: () -> Void = {}

    @Environment(AppCommandContext.self) private var commandContext
    @State private var detail: TestCandidate?
    @State private var detailError: String?
    @State private var isDetailLoading = false
    @State private var editError: String?
    @State private var isFetchingPDF = false
    @State private var commandOwner = UUID()

    private var displayedCandidate: TestCandidate {
        detail ?? candidate
    }

    private var requestIdentity: CandidateDetailRequestIdentity {
        CandidateDetailRequestIdentity(accountID: account?.id, testID: testID, candidateID: candidate.id)
    }

    /// The rename hook for the header; `nil` (a static title) without a test and account.
    private var renameAction: ((String) async -> Bool)? {
        guard testID != nil, account != nil else { return nil }

        return { newName in
            if let issue = CandidateInviteValidation.fullNameIssue(newName) {
                editError = issue
                return false
            }
            await save(CandidateUpdateOptions(fullName: newName))
        }
    }

    var body: some View {
        let candidate = displayedCandidate

        Form {
            InspectorHeader(
                title: candidate.fullName ?? candidate.email,
                badges: candidate.inspectorBadges,
                onRename: renameAction
            )

            detailLoadStatus

            Section("Properties") {
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

                if testID != nil, account != nil {
                    EditableTextRow(
                        label: "Tags",
                        value: candidate.tags?.joined(separator: ", ") ?? "",
                        prompt: "Comma-separated"
                    ) { newValue in
                        await save(CandidateUpdateOptions(tags: Self.splitList(newValue)))
                    }
                }

                if let report = candidate.reportURL, let url = URL.remoteWebURL(from: report) {
                    Link(destination: url) {
                        Label("Open report", systemImage: "doc.text")
                    }
                }

                if let pdf = candidate.pdfURL, let url = URL.remoteWebURL(from: pdf) {
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

            if testID == nil || account == nil, let tags = candidate.tags, !tags.isEmpty {
                Section("Tags") {
                    TagList(tags: tags)
                }
            }

            if let feedback = candidate.feedback, !feedback.isEmpty {
                Section("Feedback") {
                    Text(feedback).textSelection(.enabled)
                }
            }

            CandidateSummaryView(candidate: candidate)
        }
        .formStyle(.grouped)
        .navigationTitle(candidate.fullName ?? candidate.email)
        .task(id: requestIdentity) { await loadDetail(for: requestIdentity) }
        .onAppear { registerDetailCommands() }
        .activatesDetailCommands(in: commandContext, owner: commandOwner)
        .onDisappear { commandContext.clearDetailActions(owner: commandOwner) }
        // Print and Markdown export are off the bar by default but one Customize Toolbar away.
        .toolbar(id: "candidateDetail") {
            ToolbarItem(id: "reportPDF") {
                if testID != nil, account != nil {
                    Button {
                        Task { await openServerPDF() }
                    } label: {
                        if isFetchingPDF {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Report PDF", systemImage: "arrow.down.doc")
                        }
                    }
                    .disabled(isFetchingPDF)
                    .help("Fetch the candidate's report PDF from HackerRank and open it")
                }
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "print") {
                PrintReportButton(jobTitle: "Candidate: \(candidate.fullName ?? candidate.email)") {
                    CandidateReport(candidate: candidate)
                }
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "exportMarkdown") {
                MarkdownExportButton(suggestedName: candidate.fullName ?? candidate.email) {
                    MarkdownExport.candidate(candidate)
                }
            }
            .defaultCustomization(.hidden)
        }
        .alert("Couldn’t update candidate", isPresented: editErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editError ?? "")
        }
    }

    @ViewBuilder private var detailLoadStatus: some View {
        if isDetailLoading {
            Section {
                ProgressView("Loading candidate details…")
            }
        } else if let detailError {
            Section {
                Label(detailError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Button("Retry Details") {
                    Task { await loadDetail(for: requestIdentity) }
                }
            }
        }
    }

    private var editErrorPresented: Binding<Bool> {
        Binding(get: { editError != nil }, set: {
            if !$0 {
                editError = nil
            }
        })
    }

    /// "a, b, c" → ["a", "b", "c"]; nil when the field is cleared entirely.
    private static func splitList(_ text: String) -> [String]? {
        CandidateInviteValidation.normalizedTags(text)
    }

    /// Applies one field's update, then re-reads the candidate so the detail reflects the
    /// server's view.
    private func save(_ options: CandidateUpdateOptions) async -> Bool {
        guard let testID, let account else { return false }

        let client = HackerRankClient(account: account)
        let snapshot = displayedCandidate
        do {
            _ = try await client.updateCandidate(
                testID: testID,
                candidateID: candidate.id,
                options: options
            )
            do {
                detail = try await client.candidate(testID: testID, candidateID: candidate.id)
                detailError = nil
            } catch {
                detail = snapshot.applying(options)
                detailError = "Changes were saved, but the candidate details couldn’t be refreshed."
            }
            registerDetailCommands()
            onChanged()
            return true
        } catch {
            editError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// Asks the server for the candidate's report PDF link (`candidateReportPDF`) and opens
    /// it in the browser; falls back to the PDF URL already on the row when present.
    private func openServerPDF() async {
        guard CandidatePDFFetchGate.canStart(isFetching: isFetchingPDF),
              let testID, let account else { return }

        isFetchingPDF = true
        defer { isFetchingPDF = false }
        do {
            let report = try await HackerRankClient(account: account)
                .candidateReportPDF(testID: testID, candidateID: candidate.id)
            let link = report.pdfURL ?? report.url ?? displayedCandidate.pdfURL
            if let link, let url = URL.remoteWebURL(from: link) {
                BrowserSettings.open(url)
            } else {
                editError = "HackerRank returned no PDF link for this candidate."
            }
        } catch {
            editError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func registerDetailCommands() {
        let candidate = displayedCandidate
        let title = candidate.fullName ?? candidate.email
        commandContext.registerDetailActions(
            owner: commandOwner,
            print: AppCommandContext.Action(title: "Print Candidate…") {
                printReport(CandidateReport(candidate: candidate), jobTitle: "Candidate: \(title)")
            },
            exportMarkdown: AppCommandContext.Action(title: "Export Candidate as Markdown…") {
                MarkdownExport.save({ MarkdownExport.candidate(candidate) }, suggestedName: title)
            }
        )
    }

    private func loadDetail(for identity: CandidateDetailRequestIdentity) async {
        detail = nil
        detailError = nil
        registerDetailCommands()
        guard let testID, let account else { return }

        isDetailLoading = true
        let result: Result<TestCandidate, Error>
        do {
            result = try await .success(HackerRankClient(account: account).candidate(
                testID: testID,
                candidateID: candidate.id
            ))
        } catch {
            result = .failure(error)
        }
        guard !Task.isCancelled, identity == requestIdentity else { return }

        isDetailLoading = false
        switch result {
        case let .success(loaded):
            detail = loaded
        case let .failure(error):
            detailError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        registerDetailCommands()
    }
}

extension TestCandidate {
    /// Applies fields intentionally sent by an update while retaining rich read-only detail.
    func applying(_ options: CandidateUpdateOptions) -> Self {
        Self(
            id: id,
            email: email,
            fullName: options.fullName ?? fullName,
            score: score,
            percentageScore: percentageScore,
            test: test,
            status: status,
            atsState: options.atsState ?? atsState,
            integrityStatus: integrityStatus,
            attemptStartTime: attemptStartTime,
            attemptEndTime: attemptEndTime,
            tags: options.tags ?? tags,
            feedback: feedback,
            reportURL: reportURL,
            pdfURL: pdfURL,
            plagiarismStatus: plagiarismStatus,
            outOfWindowEvents: outOfWindowEvents,
            outOfWindowDuration: outOfWindowDuration,
            editorPasteCount: editorPasteCount
        )
    }
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
