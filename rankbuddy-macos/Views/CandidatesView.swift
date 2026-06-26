import SwiftUI

/// The candidates for a test, pushed from `TestDetailView`. Read-only list + detail, with
/// an opt-in "Invite Candidate" write action (#12).
struct CandidatesList: View {
    let testID: String
    let account: Account

    // The app is read-only by default; the invite action appears only when the user has
    // turned on write actions in Settings (#12).
    @AppStorage(WriteActions.defaultsKey) private var writeActionsEnabled = false
    @State private var invitePresented = false
    /// Bumped after a successful invite to refresh the list.
    @State private var reloadToken = 0

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
            contextMenu: { candidate in
                rowMenuItems(
                    copyLabel: "Copy Email",
                    copyText: candidate.email,
                    link: candidate.reportURL,
                    openLabel: "Open Report"
                )
            },
            accessoryToolbar: { writeActionsEnabled ? AnyView(inviteButton) : AnyView(EmptyView()) },
            reloadToken: reloadToken,
            row: { CandidateRow(candidate: $0) },
            detail: { CandidateDetailView(candidate: $0) }
        )
        .sheet(isPresented: $invitePresented) {
            InviteCandidateSheet(testID: testID, account: account) { reloadToken += 1 }
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
}

/// A sheet that invites a candidate to a test (#12) — the app's first write flow. Reached
/// only when write actions are enabled; it states plainly when the action affects a real
/// HackerRank account, and refreshes the list on success.
struct InviteCandidateSheet: View {
    let testID: String
    let account: Account
    /// Called after a successful invite so the caller can refresh the candidates list.
    var onInvited: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var fullName = ""
    @State private var sendEmail = true
    @State private var isSending = false
    @State private var errorMessage: String?

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A deliberately conservative check: one `@`, a non-empty local part, and a dotted
    /// domain. Enough to catch obvious typos before sending; the server is the real judge.
    private var isEmailValid: Bool {
        let parts = trimmedEmail.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }

        return !parts[0].isEmpty && parts[1].contains(".") && !parts[1].hasSuffix(".")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .disableAutocorrection(true)
                    TextField("Full name (optional)", text: $fullName)
                    Toggle("Send invitation email", isOn: $sendEmail)
                } footer: {
                    Text(consequenceText)
                        .foregroundStyle(account.isMock ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Invite Candidate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Invite") { Task { await invite() } }
                            .disabled(!isEmailValid)
                    }
                }
            }
        }
        .frame(width: 440, height: 300)
    }

    /// The footer text spelling out what the invite will do, so a live action is never a
    /// surprise.
    private var consequenceText: String {
        if account.isMock {
            return "Demo account — no real invitation is sent."
        }
        return sendEmail
            ? "This invites a real candidate to this test on HackerRank and emails them the invitation."
            : "This invites a real candidate to this test on HackerRank (no email is sent)."
    }

    private func invite() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await HackerRankClient(account: account).inviteCandidate(
                testID: testID,
                email: trimmedEmail,
                fullName: fullName,
                sendEmail: sendEmail
            )
            onInvited()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
