//
//  InterviewDetailView.swift
//  rankbuddy-macos
//

import BuddyAppKit
import HackerRankKit
import SwiftUI

// swiftlint:disable file_length type_body_length
struct InterviewDetailView: View {
    let interview: Interview
    let account: Account?
    var onChanged: () -> Void = {}
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCommandContext.self) private var commandContext
    @State private var detail: InterviewDetail?
    @State private var detailError: String?
    @State private var isDetailLoading = false
    @State private var transcript: InterviewTranscript?
    @State private var transcriptError: InterviewTranscriptFailure?
    @State private var isTranscriptLoading = false
    @State private var deletePresented = false
    @State private var deleteError: String?
    @State private var editError: String?
    /// Local overlays for saved edits: the write echo is sparse, so successful saves land
    /// here rather than waiting for the (possibly cached) list row to refresh.
    @State private var editedTitle: String?
    @State private var editedNotes: String?
    @State private var editedScheduledFrom: String?
    @State private var editedScheduledTo: String?
    @State private var commandOwner = UUID()

    init(interview: Interview, account: Account? = nil, onChanged: @escaping () -> Void = {}) {
        self.interview = interview
        self.account = account
        self.onChanged = onChanged
    }

    private var displayTitle: String {
        editedTitle ?? interview.title ?? "Interview \(interview.id)"
    }

    private var displayNotes: String {
        editedNotes ?? interview.notes ?? ""
    }

    private var displayScheduledFrom: String? {
        editedScheduledFrom ?? detail?.scheduledFrom
    }

    private var displayScheduledTo: String? {
        editedScheduledTo ?? detail?.scheduledTo
    }

    private var owningAccount: Account? {
        InterviewDetailAccountResolution.resolve(
            explicit: account,
            current: store.currentAccount,
            isMerged: store.isMergedView
        )
    }

    private var requestIdentity: InterviewDetailRequestIdentity {
        InterviewDetailRequestIdentity(
            accountID: owningAccount?.id,
            interviewID: interview.id
        )
    }

    private var reportData: InterviewReportData {
        InterviewReportData(
            interview: interview,
            title: displayTitle,
            notes: displayNotes,
            detail: detail,
            transcript: transcript
        )
    }

    /// Editing needs a single owning account. An explicitly account-scoped standalone window
    /// remains writable even while the main window shows All Accounts.
    private var canEdit: Bool {
        owningAccount != nil
    }

    /// The rename hook for the header; `nil` (a static title) when editing is unavailable.
    private var renameAction: ((String) async -> Bool)? {
        guard canEdit else { return nil }

        return { newTitle in
            if let issue = InterviewScheduleValidation.titleIssue(newTitle) {
                editError = issue
                return false
            }
            guard await update(InterviewUpdateOptions(title: newTitle)) else { return false }

            editedTitle = newTitle
            return true
        }
    }

    private var detailURL: URL? {
        URL.remoteWebURL(from: interview.url)
    }

    private var favoriteReference: FavoriteRef? {
        owningAccount.map {
            FavoriteRef(accountID: $0.id.uuidString, collection: .interviews,
                        itemID: interview.id, title: displayTitle)
        }
    }

    var body: some View {
        Form {
            InspectorHeader(title: displayTitle, badges: interview.inspectorBadges, onRename: renameAction)

            detailLoadStatus

            Section("Properties") {
                OptionalRow("Status", DisplayFormat.enumLabel(interview.status))
                scheduledRow(label: "Scheduled start", raw: displayScheduledFrom) { newDate in
                    guard let end = DisplayFormat.parseDate(displayScheduledTo),
                          Self.isValidSchedule(start: newDate, end: end)
                    else {
                        editError = "Scheduled start must be before scheduled end."
                        return false
                    }

                    let value = Self.iso8601.string(from: newDate)
                    guard await update(InterviewUpdateOptions(from: value)) else { return false }

                    editedScheduledFrom = value
                    return true
                }
                scheduledRow(label: "Scheduled end", raw: displayScheduledTo) { newDate in
                    guard let start = DisplayFormat.parseDate(displayScheduledFrom),
                          Self.isValidSchedule(start: start, end: newDate)
                    else {
                        editError = "Scheduled end must be after scheduled start."
                        return false
                    }

                    let value = Self.iso8601.string(from: newDate)
                    guard await update(InterviewUpdateOptions(to: value)) else { return false }

                    editedScheduledTo = value
                    return true
                }
                OptionalRow("Created", DisplayFormat.date(interview.createdAt))
                OptionalRow("Updated", DisplayFormat.date(interview.updatedAt))
                OptionalRow("Ended", DisplayFormat.date(interview.endedAt))
                OptionalRow("Thumbs up", interview.thumbsUp.map(String.init))

                if let report = interview.reportURL, let url = URL.remoteWebURL(from: report) {
                    Link(destination: url) {
                        Label("Open report", systemImage: "doc.text")
                    }
                }

                if let result = detail?.resultURL, let url = URL.remoteWebURL(from: result) {
                    Link(destination: url) {
                        Label("Open result", systemImage: "checkmark.seal")
                    }
                }

                if let resume = detail?.resumeURL, let url = URL.remoteWebURL(from: resume) {
                    Link(destination: url) {
                        Label("Open résumé", systemImage: "doc.richtext")
                    }
                }
            }

            if let detail, detail.hasPeople {
                Section("People") {
                    if let candidate = detail.candidate {
                        OptionalRow("Candidate", candidate.displayName)
                    }
                    if let user = detail.user {
                        OptionalRow("Created by", user.displayName)
                    }
                    ForEach(Array(detail.interviewers.enumerated()), id: \.offset) { _, person in
                        OptionalRow("Interviewer", person.displayName)
                    }
                }
            }

            if canEdit {
                Section("Notes") {
                    InlineEditableText(text: displayNotes, placeholder: "Add notes") { newNotes in
                        if let issue = InterviewScheduleValidation.notesIssue(newNotes) {
                            editError = issue
                            return false
                        }
                        guard await update(InterviewUpdateOptions(notes: newNotes)) else { return false }

                        editedNotes = newNotes
                        return true
                    }
                }
            } else if !displayNotes.isEmpty {
                Section("Notes") {
                    Text(displayNotes)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let feedback = interview.feedback, !feedback.isEmpty {
                Section("Feedback") {
                    Text(feedback)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            transcriptSection
        }
        .formStyle(.grouped)
        .navigationTitle(displayTitle)
        .nativeResourceActions(.interview, account: owningAccount, path: ["interview_id": interview.id],
                               showsMenu: owningAccount != nil || detailURL != nil, menuContent: {
                                   DetailLinkMenuContent(url: detailURL, noun: "interview", favorite: favoriteReference)
                               }, onSaved: {
                                   onChanged()
                                   Task { await loadDetail(for: requestIdentity) }
                               })
        .task(id: requestIdentity) { await loadDetail(for: requestIdentity) }
        .onAppear { registerDetailCommands() }
        .activatesDetailCommands(in: commandContext, owner: commandOwner)
        .onDisappear { commandContext.clearDetailActions(owner: commandOwner) }
        .advertisesItemActivity(
            collection: .interviews,
            itemID: interview.id,
            title: displayTitle,
            account: account,
            webURL: URL.remoteWebURL(from: interview.url)
        )
        .windowToolbar(id: "interviewDetail") {
            DetailLinkToolbarContent(url: detailURL, noun: "interview", favorite: favoriteReference)
            ToolbarItem(id: "print") {
                PrintReportButton(jobTitle: "Interview: \(displayTitle)") {
                    InterviewReport(data: reportData)
                }
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "exportMarkdown") {
                let snapshot = reportData
                MarkdownExportButton(suggestedName: snapshot.title) {
                    MarkdownExport.interview(snapshot)
                }
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "delete") {
                Button(role: .destructive) {
                    deletePresented = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete this interview")
                .disabled(!canEdit)
            }
            .defaultCustomization(.hidden)
        }
        .confirmationDialog("Delete “\(displayTitle)”?", isPresented: $deletePresented, titleVisibility: .visible) {
            Button("Delete Interview", role: .destructive) {
                Task { await deleteInterview() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the interview on HackerRank. This can’t be undone.")
        }
        .alert("Couldn’t delete interview", isPresented: deleteErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .alert("Couldn’t update interview", isPresented: editErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editError ?? "")
        }
    }

    private static let iso8601 = ISO8601DateFormatter()

    @ViewBuilder private var detailLoadStatus: some View {
        if isDetailLoading {
            Section {
                ProgressView("Loading interview details…")
            }
        } else if let detailError {
            Section {
                Label(detailError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Button("Retry Details") {
                    Task { await loadInterviewDetail(for: requestIdentity) }
                }
            }
        }
    }

    private var transcriptSection: some View {
        Section("Transcript") {
            if isTranscriptLoading {
                ProgressView("Loading transcript…")
            } else if transcriptError == .transcriptionDisabled {
                TranscriptionDisabledView()
            } else if case let .requestFailed(message) = transcriptError {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Button("Retry") {
                    Task { await loadTranscript(for: requestIdentity) }
                }
            } else if let messages = transcript?.messages, !messages.isEmpty {
                ForEach(TranscriptMessageOccurrence.rows(messages)) { row in
                    TranscriptMessageRow(message: row.message)
                }
            } else {
                ContentUnavailableView(
                    "No Transcript",
                    systemImage: "text.bubble",
                    description: Text("This interview does not have any transcript messages.")
                )
            }
        }
    }

    nonisolated static func isValidSchedule(start: Date, end: Date) -> Bool {
        start < end
    }

    private var deleteErrorPresented: Binding<Bool> {
        Binding(get: { deleteError != nil }, set: {
            if !$0 {
                deleteError = nil
            }
        })
    }

    private var editErrorPresented: Binding<Bool> {
        Binding(get: { editError != nil }, set: {
            if !$0 {
                editError = nil
            }
        })
    }

    @ViewBuilder
    private func scheduledRow(
        label: String,
        raw: String?,
        commit: @escaping (Date) async -> Bool
    ) -> some View {
        if canEdit, let date = DisplayFormat.parseDate(raw) {
            EditableDateRow(label: label, value: date, commit: commit)
        } else {
            OptionalRow(label, DisplayFormat.date(raw))
        }
    }

    /// Applies one field's update, then re-reads the detail so the scheduled window and any
    /// other server-derived fields reflect the write.
    private func update(_ options: InterviewUpdateOptions) async -> Bool {
        guard let account = owningAccount else { return false }

        do {
            _ = try await HackerRankClient(account: account).updateInterview(id: interview.id, options: options)
            if let refreshed = try? await HackerRankClient(account: account).interview(id: interview.id) {
                detail = refreshed
            }
            onChanged()
            return true
        } catch {
            editError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func registerDetailCommands() {
        commandContext.registerDetailActions(
            owner: commandOwner,
            print: AppCommandContext.Action(title: "Print Interview…") {
                printReport(
                    InterviewReport(data: reportData),
                    jobTitle: "Interview: \(displayTitle)"
                )
            },
            exportMarkdown: AppCommandContext.Action(title: "Export Interview as Markdown…") {
                let snapshot = reportData
                MarkdownExport.save(
                    { MarkdownExport.interview(snapshot) },
                    suggestedName: snapshot.title
                )
            }
        )
    }

    /// Fetches the richer detail and transcript for the selected interview (#103). Both are
    /// best-effort: failures leave the base list-row detail intact. Skipped in the merged view,
    /// where a single owning account isn't known, so the wrong account is never queried.
    private func loadDetail(for identity: InterviewDetailRequestIdentity) async {
        editedTitle = nil
        editedNotes = nil
        editedScheduledFrom = nil
        editedScheduledTo = nil
        detail = nil
        detailError = nil
        isDetailLoading = true
        transcript = nil
        transcriptError = nil
        isTranscriptLoading = true
        guard let account = owningAccount else {
            isDetailLoading = false
            isTranscriptLoading = false
            return
        }

        let client = HackerRankClient(account: account)
        async let fetchedDetail = Self.fetchDetail(client: client, interviewID: interview.id)
        async let fetchedTranscript = Self.fetchTranscript(client: client, interviewID: interview.id)
        let loaded = await (fetchedDetail, fetchedTranscript)
        guard !Task.isCancelled, identity == requestIdentity else { return }

        applyDetailResult(loaded.0)
        applyTranscriptResult(loaded.1)
    }

    private func loadInterviewDetail(for identity: InterviewDetailRequestIdentity) async {
        detail = nil
        detailError = nil
        isDetailLoading = true
        guard let account = owningAccount else {
            isDetailLoading = false
            return
        }

        let result = await Self.fetchDetail(
            client: HackerRankClient(account: account),
            interviewID: interview.id
        )
        guard !Task.isCancelled, identity == requestIdentity else { return }

        applyDetailResult(result)
    }

    private func applyDetailResult(_ result: DetailLoadResult) {
        isDetailLoading = false
        switch result {
        case let .loaded(value):
            detail = value
        case let .failed(message):
            detailError = message
        }
    }

    private func loadTranscript(for identity: InterviewDetailRequestIdentity) async {
        transcript = nil
        transcriptError = nil
        isTranscriptLoading = true
        guard let account = owningAccount else {
            isTranscriptLoading = false
            return
        }

        let result = await Self.fetchTranscript(
            client: HackerRankClient(account: account),
            interviewID: interview.id
        )
        guard !Task.isCancelled, identity == requestIdentity else { return }

        applyTranscriptResult(result)
    }

    private func applyTranscriptResult(_ result: TranscriptLoadResult) {
        isTranscriptLoading = false
        switch result {
        case let .loaded(value):
            transcript = value
        case let .failed(message):
            transcriptError = message
        }
    }

    private enum TranscriptLoadResult {
        case loaded(InterviewTranscript)
        case failed(InterviewTranscriptFailure)
    }

    private enum DetailLoadResult {
        case loaded(InterviewDetail)
        case failed(String)
    }

    private nonisolated static func fetchDetail(
        client: HackerRankClient,
        interviewID: String
    ) async -> DetailLoadResult {
        do {
            return try await .loaded(client.interview(id: interviewID))
        } catch {
            return .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private nonisolated static func fetchTranscript(
        client: HackerRankClient,
        interviewID: String
    ) async -> TranscriptLoadResult {
        do {
            return try await .loaded(client.interviewTranscript(id: interviewID))
        } catch {
            return .failed(InterviewTranscriptFailure(error: error))
        }
    }

    private func deleteInterview() async {
        guard let account = owningAccount else { return }

        do {
            try await HackerRankClient(account: account).deleteInterview(id: interview.id)
            onChanged()
            dismiss()
        } catch {
            deleteError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// swiftlint:enable type_body_length

struct TranscriptionDisabledView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Transcription not enabled", systemImage: "text.bubble")
                .font(.headline)
            Text("No transcript is available because interview transcription is turned off in HackerRank.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One message in the interview transcript, styled to distinguish the candidate from the
/// interviewers (#103).
nonisolated struct TranscriptMessageOccurrence: Identifiable {
    let id: Int
    let message: InterviewMessage

    static func rows(_ messages: [InterviewMessage]) -> [Self] {
        messages.enumerated().map { Self(id: $0.offset, message: $0.element) }
    }
}

struct TranscriptMessageRow: View {
    let message: InterviewMessage

    private var isCandidate: Bool {
        message.candidate ?? false
    }

    private var speaker: String {
        message.author ?? (isCandidate ? "Candidate" : "Interviewer")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label(speaker, systemImage: isCandidate ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCandidate ? Color.accentColor : Color.secondary)
                Spacer()
                if let sentAt = message.sentAt {
                    Text(sentAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let text = message.text, !text.isEmpty {
                Text(text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Transcript") {
    let json = #"""
    {"messages":[
      {"messageId":"m1","author":"Ian Interviewer","candidate":false,"timestamp":1746450000000,
       "text":"Welcome! Let's start with a brief warm-up question."}
    ]}
    """#
    let transcript = (try? JSONDecoder().decode(InterviewTranscript.self, from: Data(json.utf8)))
    return Form {
        Section("Transcript") {
            ForEach(TranscriptMessageOccurrence.rows(transcript?.messages ?? [])) { row in
                TranscriptMessageRow(message: row.message)
            }
        }
    }
    .formStyle(.grouped)
    .frame(width: 460, height: 320)
}

#Preview("Transcription not enabled") {
    Form {
        Section("Transcript") {
            TranscriptionDisabledView()
        }
    }
    .formStyle(.grouped)
    .frame(width: 460, height: 200)
}
