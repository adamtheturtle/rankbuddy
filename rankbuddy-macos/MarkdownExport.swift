//
//  MarkdownExport.swift
//  rankbuddy-macos
//

import AppKit
import HackerRankKit
import SwiftUI
import UniformTypeIdentifiers

/// Markdown export for the detail views (#50) — alongside Print/PDF (#13) and CSV (#39).
/// Mirrors PadBuddy's "Export as Markdown". The document builders are pure and unit-testable;
/// `save` writes through the system save panel (powerbox — no file entitlement).
enum MarkdownExport {
    enum Limits {
        nonisolated static let inlineCharacters = 500
        nonisolated static let proseCharacters = 100_000
    }

    /// A `## Heading` over `- **Label:** value` lines; empty (dropped) when no field has a value.
    nonisolated static func section(_ title: String, _ fields: [(String, String?)]) -> String {
        let lines = fields.compactMap { label, value in
            value.map { "- **\(inlineText(label)):** \(inlineText($0))" }
        }
        return lines.isEmpty ? "" : "## \(inlineText(title))\n" + lines.joined(separator: "\n")
    }

    /// A `## Heading` over a block of free text; empty when the text is missing.
    nonisolated static func textSection(_ title: String, _ text: String?) -> String {
        guard let text, !text.isEmpty else { return "" }

        let bounded = boundedText(text, maximumCharacters: Limits.proseCharacters)
        let suffix = bounded.omitted ? "\n\n_Content truncated for export._" : ""
        return "## \(inlineText(title))\n\(escapedMarkdown(bounded.text))\(suffix)"
    }

    /// Assembles a document: an `# Title`, an italic subtitle, then the non-empty sections.
    nonisolated static func document(title: String, subtitle: String, sections: [String]) -> String {
        (["# \(inlineText(title))", "_\(inlineText(subtitle))_"] + sections.filter { !$0.isEmpty })
            .joined(separator: "\n\n") + "\n"
    }

    /// Strips HTML tags and decodes the few common entities, for embedding an HTML field (e.g.
    /// a test's instructions) as plain Markdown text. `<style>`/`<script>` elements are dropped
    /// with their contents — HackerRank prefixes problem statements with a large CSS block, and
    /// sometimes sends *only* that block, which should read as empty rather than as a wall of CSS.
    nonisolated static func plainText(fromHTML html: String) -> String {
        let content = html.replacingOccurrences(
            of: "(?is)<(style|script)\\b[^>]*>.*?</\\1>",
            with: "",
            options: .regularExpression
        )
        let bounded = boundedText(content, maximumCharacters: Limits.proseCharacters)
        let withBreaks = bounded.text
            .replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(
                of: "(?i)</(?:p|div|li|h[1-6]|tr)\\s*>",
                with: "\n",
                options: .regularExpression
            )
        let text = HTMLCodeBlocks.stripTags(withBreaks)
        let decoded = decodeHTMLEntitiesOnce(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return bounded.omitted ? decoded + "\n\nContent truncated for export." : decoded
    }

    private nonisolated static func decodeHTMLEntitiesOnce(_ text: String) -> String {
        HTMLCodeBlocks.decodeEntities(text)
    }

    nonisolated static func boundedText(_ text: String, maximumCharacters: Int) -> (text: String, omitted: Bool) {
        let prefix = text.prefix(maximumCharacters)
        return (String(prefix), prefix.endIndex != text.endIndex)
    }

    nonisolated static func inlineText(_ text: String) -> String {
        let bounded = boundedText(text, maximumCharacters: Limits.inlineCharacters)
        let normalized = bounded.text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return escapedMarkdown(normalized) + (bounded.omitted ? "..." : "")
    }

    /// Escapes API and user-provided text while leaving the report's own Markdown structure
    /// intact. Escaping everywhere (rather than only at line starts) also prevents values from
    /// completing emphasis, links, images, code spans, tables, or HTML constructs.
    nonisolated static func escapedMarkdown(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            if "\\`*_{}[]<>()#+-!|".contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    private nonisolated static func formattedDate(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let parsed = fractional.date(from: value) ?? plain.date(from: value) else { return value }

        return parsed.formatted(date: .abbreviated, time: .shortened)
    }

    private nonisolated static func formattedInterval(_ seconds: Double?) -> String? {
        guard let seconds, seconds > 0 else { return nil }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds)
    }

    private nonisolated static func formattedList(_ values: [String]?) -> String? {
        guard let values, !values.isEmpty else { return nil }

        return values.formatted(.list(type: .and))
    }

    private nonisolated static func formattedLanguages(_ codes: [String]?) -> String? {
        guard let codes, !codes.isEmpty else { return nil }

        return codes.map(DisplayFormat.languageName).formatted(.list(type: .and))
    }

    // MARK: - Per-collection documents

    nonisolated static func candidate(_ candidate: TestCandidate) -> String {
        document(title: candidate.fullName ?? candidate.email, subtitle: "HackerRank Candidate Report", sections: [
            section("Candidate", [
                ("Name", candidate.fullName), ("Email", candidate.email),
                ("Attempt", candidate.attemptStatusLabel), ("Pipeline", candidate.pipelineStatusLabel),
                ("Score", candidate.score.map { $0.formatted() }),
                ("Percentage", candidate.percentageScore.map { "\($0.formatted())%" }),
                ("Integrity", candidate.integrityStatus),
                ("Plagiarism", candidate.plagiarismStatus.map { $0 ? "Flagged" : "Clear" }),
                ("Started", formattedDate(candidate.attemptStartTime)),
                ("Ended", formattedDate(candidate.attemptEndTime))
            ]),
            candidate.hasProctoringSignals ? section("Proctoring", [
                ("Left test window", candidate.outOfWindowEvents.map { "\($0)×" }),
                ("Time outside window", formattedInterval(candidate.outOfWindowDuration)),
                ("Editor pastes", candidate.editorPasteCount.map { "\($0)×" })
            ]) : "",
            textSection("Tags", candidate.tags.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") }),
            textSection("Feedback", candidate.feedback)
        ])
    }

    nonisolated static func test(_ test: Test) -> String {
        self.test(TestReportData(test: test))
    }

    nonisolated static func test(_ report: TestReportData) -> String {
        let test = report.test
        return document(title: test.name, subtitle: "HackerRank Test Report", sections: [
            section("Test", [
                ("State", DisplayFormat.enumLabel(test.state)), ("Unique ID", test.uniqueID),
                ("Duration", test.duration.map { "\($0) min" }),
                ("Cutoff", test.cutoffScore.map(String.init)),
                ("Questions", test.questions.map { "\($0.count)" }),
                ("Starts", formattedDate(test.startTime)), ("Ends", formattedDate(test.endTime)),
                ("Created", formattedDate(test.createdAt)),
                ("Library", formattedList(test.library.map { [$0] })),
                ("Role", formattedList(test.role.map { [$0] })),
                ("Skills", formattedList(test.skills)),
                ("Type", formattedList(test.type.map { [$0] })),
                ("Languages", formattedLanguages(test.languages)),
                ("Proctoring", test.enableProctoring.map { $0 ? "Enabled" : "Disabled" }),
                ("Shuffle questions", test.shuffleQuestions.map { $0 ? "Yes" : "No" }),
                ("Starred", test.starred.map { $0 ? "Yes" : "No" }),
                ("Locked", test.locked.map { $0 ? "Yes" : "No" }),
                ("Draft", test.draft.map { $0 ? "Yes" : "No" }),
                ("MCQ correct score", report.mcqCorrectScore.map { $0.formatted() }),
                ("MCQ incorrect score", report.mcqIncorrectScore.map { $0.formatted() })
            ]),
            section("Access", [
                ("Short login URL", report.shortLoginURL),
                ("Public login URL", report.publicLoginURL),
                ("Access password", report.accessPassword)
            ]),
            section("Inviters", report.inviters.map {
                ($0.displayName, [$0.email, $0.role].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " — "))
            }),
            textSection("Tags", test.tags.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") }),
            textSection("Instructions", test.instructions.map(plainText(fromHTML:)))
        ])
    }

    nonisolated static func question(_ question: Question) -> String {
        self.question(QuestionReportData(question: question))
    }

    nonisolated static func question(_ report: QuestionReportData) -> String {
        let question = report.question
        return document(title: question.name, subtitle: "HackerRank Question Report", sections: [
            section("Question", [
                ("Type", DisplayFormat.enumLabel(question.type)), ("Unique ID", question.uniqueID),
                ("Status", DisplayFormat.enumLabel(question.status)),
                ("Max score", question.maxScore.map { $0.formatted() }),
                ("Recommended duration", question.recommendedDuration.map { "\($0) minutes" }),
                ("Created", formattedDate(question.createdAt)),
                ("Languages", formattedLanguages(question.languages)),
                ("Skills", formattedList(question.skills))
            ]),
            section("Options", report.options.indices.map {
                ("Option \($0 + 1)", report.optionLabel(at: $0))
            }),
            textSection("Correct answer", report.correctAnswer),
            textSection("Internal notes", report.internalNotes.map(plainText(fromHTML:))),
            textSection("Tags", question.tags.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") }),
            textSection("Problem statement", question.problemStatement.map(plainText(fromHTML:)))
        ])
    }

    nonisolated static func interview(_ interview: Interview, title: String? = nil, notes: String? = nil) -> String {
        self.interview(InterviewReportData(interview: interview, title: title, notes: notes))
    }

    nonisolated static func interview(_ report: InterviewReportData) -> String {
        let interview = report.interview
        return document(
            title: report.title,
            subtitle: "HackerRank Interview Report",
            sections: [
                section("Interview", [
                    ("Status", DisplayFormat.enumLabel(interview.status)),
                    ("Scheduled start", formattedDate(report.detail?.scheduledFrom)),
                    ("Scheduled end", formattedDate(report.detail?.scheduledTo)),
                    ("Created", formattedDate(interview.createdAt)),
                    ("Updated", formattedDate(interview.updatedAt)),
                    ("Ended", formattedDate(interview.endedAt)),
                    ("Thumbs up", interview.thumbsUp.map(String.init)),
                    ("Report URL", interview.reportURL),
                    ("Result URL", report.detail?.resultURL),
                    ("Résumé URL", report.detail?.resumeURL)
                ]),
                section("People", [
                    ("Candidate", report.detail?.candidate?.displayName),
                    ("Created by", report.detail?.user?.displayName)
                ] + (report.detail?.interviewers ?? []).map { ("Interviewer", $0.displayName) }),
                textSection("Notes", report.notes),
                textSection("Feedback", interview.feedback),
                textSection("Transcript", report.transcriptText)
            ]
        )
    }

    // MARK: - Saving

    @MainActor
    static func save(_ markdown: @escaping @Sendable () -> String, suggestedName: String) {
        FileExport.save(
            markdown,
            suggestedName: "\(suggestedName).md",
            allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText],
            failureTitle: "Couldn’t export Markdown"
        )
    }
}

/// A toolbar button that exports a Markdown report (#50).
struct MarkdownExportButton: View {
    let suggestedName: String
    let markdown: @Sendable () -> String

    var body: some View {
        Button {
            MarkdownExport.save(markdown, suggestedName: suggestedName)
        } label: {
            Label("Export as Markdown…", systemImage: "doc.plaintext")
        }
        .help("Export as a Markdown file")
    }
}
