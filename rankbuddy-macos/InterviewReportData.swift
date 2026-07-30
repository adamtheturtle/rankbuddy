//
//  InterviewReportData.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit

nonisolated struct InterviewDetailRequestIdentity: Hashable {
    let accountID: UUID?
    let interviewID: String
}

nonisolated enum InterviewDetailAccountResolution {
    static func resolve(explicit: Account?, current: Account?, isMerged: Bool) -> Account? {
        explicit ?? (isMerged ? nil : current)
    }
}

/// Everything currently displayed by an interview inspector, captured for print and export.
nonisolated struct InterviewReportData {
    let interview: Interview
    let title: String
    let notes: String
    let detail: InterviewDetail?
    let messages: [InterviewMessage]

    init(
        interview: Interview,
        title: String? = nil,
        notes: String? = nil,
        detail: InterviewDetail? = nil,
        transcript: InterviewTranscript? = nil
    ) {
        self.interview = interview
        self.title = title ?? interview.title ?? "Interview \(interview.id)"
        self.notes = notes ?? interview.notes ?? ""
        self.detail = detail
        messages = transcript?.messages ?? []
    }

    var transcriptText: String? {
        let lines = messages.compactMap { message -> String? in
            guard let text = message.text, !text.isEmpty else { return nil }

            return "\(message.reportSpeaker): \(text)"
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }
}

nonisolated extension InterviewMessage {
    var reportSpeaker: String {
        author ?? email ?? (candidate == true ? "Candidate" : "Interviewer")
    }
}
