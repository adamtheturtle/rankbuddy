//
//  InterviewDetailView.swift
//  rankbuddy-macos
//

import BuddyAppKit
import HackerRankKit
import SwiftUI

// swiftlint:disable type_body_length
/// Detail for a single interview. Beyond the list row's fields, it fetches the richer
/// single-interview read and the conversation transcript on selection (#103); both load
/// lazily and degrade silently (e.g. in merged view, where the owning account is ambiguous).
/// Scheduled fields save individually through `updateInterview` (#147).
struct InterviewDetailView: View {
    let interview: Interview
    var onChanged: () -> Void = {}
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCommandContext.self) private var commandContext
    @State private var detail: InterviewDetail?
    @State private var transcript: InterviewTranscript?
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

    /// Editing needs a single owning account, so the merged view stays read-only.
    private var canEdit: Bool {
        !store.isMergedView && store.currentAccount != nil
    }

    /// The rename hook for the header; `nil` (a static title) when editing is unavailable.
    private var renameAction: ((String) async -> Bool)? {
        guard canEdit else { return nil }

        return { newTitle in
            guard await update(InterviewUpdateBody(title: newTitle)) else { return false }

            editedTitle = newTitle
            return true
        }
    }

    var body: some View {
        Form {
            InspectorHeader(title: displayTitle, badges: interview.inspectorBadges, onRename: renameAction)

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
                    guard await update(InterviewUpdateBody(from: value)) else { return false }

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
                    guard await update(InterviewUpdateBody(endsAt: value)) else { return false }

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
                        guard await update(InterviewUpdateBody(notes: newNotes)) else { return false }

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

            if let messages = transcript?.messages, !messages.isEmpty {
                Section("Transcript") {
                    ForEach(messages) { message in
                        TranscriptMessageRow(message: message)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(displayTitle)
        .task(id: interview.id) { await loadDetail() }
        .onAppear { registerDetailCommands() }
        .activatesDetailCommands(in: commandContext, owner: commandOwner)
        .onDisappear { commandContext.clearDetailActions(owner: commandOwner) }
        .advertisesItemActivity(
            collection: .interviews,
            itemID: interview.id,
            title: displayTitle,
            webURL: URL.remoteWebURL(from: interview.url)
        )
        // Share and Open (the interview on HackerRank) lead the bar like PadBuddy; Print and
        // Markdown export are off the bar by default but one Customize Toolbar away.
        .toolbar(id: "interviewDetail") {
            DetailLinkToolbarContent(url: URL.remoteWebURL(from: interview.url), noun: "interview")
            ToolbarItem(id: "print") {
                PrintReportButton(jobTitle: "Interview: \(displayTitle)") {
                    InterviewReport(interview: interview, title: displayTitle, notes: displayNotes)
                }
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "exportMarkdown") {
                let title = displayTitle
                let notes = displayNotes
                MarkdownExportButton(suggestedName: title) {
                    MarkdownExport.interview(interview, title: title, notes: notes)
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
                .disabled(store.currentAccount == nil || store.isMergedView)
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

    nonisolated static func isValidSchedule(start: Date, end: Date) -> Bool {
        start < end
    }

    private var deleteErrorPresented: Binding<Bool> {
        Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
    }

    private var editErrorPresented: Binding<Bool> {
        Binding(get: { editError != nil }, set: { if !$0 { editError = nil } })
    }

    /// The scheduled start/end row: a date picker when the field is present and editable,
    /// the usual read-only row otherwise. Scheduling from scratch stays with the create flow.
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
    private func update(_ body: InterviewUpdateBody) async -> Bool {
        guard !store.isMergedView, let account = store.currentAccount else { return false }

        do {
            _ = try await HackerRankClient(account: account).updateInterview(id: interview.id, body: body)
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
                    InterviewReport(interview: interview, title: displayTitle, notes: displayNotes),
                    jobTitle: "Interview: \(displayTitle)"
                )
            },
            exportMarkdown: AppCommandContext.Action(title: "Export Interview as Markdown…") {
                let title = displayTitle
                let notes = displayNotes
                MarkdownExport.save(
                    { MarkdownExport.interview(interview, title: title, notes: notes) },
                    suggestedName: title
                )
            }
        )
    }

    /// Fetches the richer detail and transcript for the selected interview (#103). Both are
    /// best-effort: failures leave the base list-row detail intact. Skipped in the merged view,
    /// where a single owning account isn't known, so the wrong account is never queried.
    private func loadDetail() async {
        detail = nil
        transcript = nil
        guard !store.isMergedView, let account = store.currentAccount else { return }

        let client = HackerRankClient(account: account)
        async let fetchedDetail = try? client.interview(id: interview.id)
        async let fetchedTranscript = try? client.interviewTranscript(id: interview.id)
        detail = await fetchedDetail
        transcript = await fetchedTranscript
    }

    private func deleteInterview() async {
        guard !store.isMergedView, let account = store.currentAccount else { return }

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

/// The `PUT /interviews/{id}` body. Mirrors HackerRankKit's typed request (which lands in a
/// future Kit release); Kit 0.4.0's `updateInterview` accepts any `Encodable` body, and the
/// synthesized encoding omits `nil` fields so each save sends only the field it changes.
nonisolated struct InterviewUpdateBody: Encodable {
    var title: String?
    var from: String?
    var endsAt: String?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case title
        case from
        case endsAt = "to"
        case notes
    }
}

/// One message in the interview transcript, styled to distinguish the candidate from the
/// interviewers (#103).
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
                if let timestamp = message.timestamp {
                    Text(Date(timeIntervalSince1970: TimeInterval(timestamp)), style: .time)
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
      {"messageId":"m1","author":"Ian Interviewer","candidate":false,"timestamp":1746450000,
       "text":"Welcome! Let's start with a brief warm-up question."}
    ]}
    """#
    let transcript = (try? JSONDecoder().decode(InterviewTranscript.self, from: Data(json.utf8)))
    return Form {
        Section("Transcript") {
            ForEach(transcript?.messages ?? []) { message in
                TranscriptMessageRow(message: message)
            }
        }
    }
    .formStyle(.grouped)
    .frame(width: 460, height: 320)
}
