//
//  InterviewDetailView.swift
//  rankbuddy-macos
//

import BuddyAppKit
import HackerRankKit
import SwiftUI

/// Read-only detail for a single interview. Beyond the list row's fields, it fetches the
/// richer single-interview read and the conversation transcript on selection (#103); both load
/// lazily and degrade silently (e.g. in merged view, where the owning account is ambiguous).
struct InterviewDetailView: View {
    let interview: Interview
    @Environment(AccountStore.self) private var store
    @Environment(AppCommandContext.self) private var commandContext
    @State private var detail: InterviewDetail?
    @State private var transcript: InterviewTranscript?

    var body: some View {
        Form {
            InspectorHeader(title: interview.title ?? "Interview", badges: interview.inspectorBadges)

            Section("Properties") {
                OptionalRow("Status", interview.status.capitalized)
                OptionalRow("Scheduled start", DisplayFormat.date(detail?.scheduledFrom))
                OptionalRow("Scheduled end", DisplayFormat.date(detail?.scheduledTo))
                OptionalRow("Created", DisplayFormat.date(interview.createdAt))
                OptionalRow("Updated", DisplayFormat.date(interview.updatedAt))
                OptionalRow("Ended", DisplayFormat.date(interview.endedAt))
                OptionalRow("Thumbs up", interview.thumbsUp.map(String.init))

                if let url = URL(string: interview.url) {
                    Link(destination: url) {
                        Label("Open in browser", systemImage: "safari")
                    }
                }

                if let report = interview.reportURL, let url = URL(string: report) {
                    Link(destination: url) {
                        Label("Open report", systemImage: "doc.text")
                    }
                }

                if let result = detail?.resultURL, let url = URL(string: result) {
                    Link(destination: url) {
                        Label("Open result", systemImage: "checkmark.seal")
                    }
                }

                if let resume = detail?.resumeURL, let url = URL(string: resume) {
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

            if let messages = transcript?.messages, !messages.isEmpty {
                Section("Transcript") {
                    ForEach(messages) { message in
                        TranscriptMessageRow(message: message)
                    }
                }
            }
        }
        .inspectorFormStyle()
        .navigationTitle(interview.title ?? "Interview")
        .task(id: interview.id) { await loadDetail() }
        .onAppear { registerDetailCommands() }
        .onDisappear { commandContext.clearDetailActions() }
        .advertisesItemActivity(
            collection: .interviews,
            itemID: interview.id,
            title: interview.title ?? "Interview \(interview.id)",
            webURL: URL(string: interview.url)
        )
        // Share and Open (the interview on HackerRank) lead the bar like PadBuddy; Print and
        // Markdown export are off the bar by default but one Customize Toolbar away.
        .toolbar(id: "interviewDetail") {
            DetailLinkToolbarContent(url: URL(string: interview.url), noun: "interview")
            ToolbarItem(id: "print") {
                PrintReportButton(jobTitle: "Interview: \(interview.title ?? interview.id)") {
                    InterviewReport(interview: interview)
                }
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "exportMarkdown") {
                MarkdownExportButton(suggestedName: interview.title ?? "interview-\(interview.id)") {
                    MarkdownExport.interview(interview)
                }
            }
            .defaultCustomization(.hidden)
        }
    }

    private func registerDetailCommands() {
        let title = interview.title ?? "Interview \(interview.id)"
        commandContext.print = AppCommandContext.Action(title: "Print Interview…") {
            printReport(InterviewReport(interview: interview), jobTitle: "Interview: \(title)")
        }
        commandContext.exportMarkdown = AppCommandContext.Action(title: "Export Interview as Markdown…") {
            MarkdownExport.save(MarkdownExport.interview(interview), suggestedName: title)
        }
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
      {"messageId":"m1","author":"Ian Interviewer","candidate":false,
       "timestamp":1746450000,"text":"Welcome! Let's start with a brief warm-up question."},
      {"messageId":"m2","author":"Ada Lovelace","candidate":true,
       "timestamp":1746450060,"text":"Sounds good, I'm ready when you are."},
      {"messageId":"m3","author":"Ian Interviewer","candidate":false,
       "timestamp":1746450120,"text":"Great. Can you walk me through your approach to the problem?"}
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
