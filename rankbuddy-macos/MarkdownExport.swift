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
    static func section(_ title: String, _ fields: [(String, String?)]) -> String {
        let lines = fields.compactMap { label, value in
            value.map { "- **\(inlineText(label)):** \(inlineText($0))" }
        }
        return lines.isEmpty ? "" : "## \(inlineText(title))\n" + lines.joined(separator: "\n")
    }

    /// A `## Heading` over a block of free text; empty when the text is missing.
    static func textSection(_ title: String, _ text: String?) -> String {
        guard let text, !text.isEmpty else { return "" }

        let bounded = boundedText(text, maximumCharacters: Limits.proseCharacters)
        let suffix = bounded.omitted ? "\n\n_Content truncated for export._" : ""
        return "## \(inlineText(title))\n\(bounded.text)\(suffix)"
    }

    /// Assembles a document: an `# Title`, an italic subtitle, then the non-empty sections.
    static func document(title: String, subtitle: String, sections: [String]) -> String {
        (["# \(inlineText(title))", "_\(inlineText(subtitle))_"] + sections.filter { !$0.isEmpty })
            .joined(separator: "\n\n") + "\n"
    }

    /// Strips HTML tags and decodes the few common entities, for embedding an HTML field (e.g.
    /// a test's instructions) as plain Markdown text. `<style>`/`<script>` elements are dropped
    /// with their contents — HackerRank prefixes problem statements with a large CSS block, and
    /// sometimes sends *only* that block, which should read as empty rather than as a wall of CSS.
    nonisolated static func plainText(fromHTML html: String) -> String {
        let bounded = boundedText(html, maximumCharacters: Limits.proseCharacters)
        let text = bounded.text
            .replacingOccurrences(
                of: "(?is)<(style|script)\\b[^>]*>.*?</\\1>",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return bounded.omitted ? text + "\n\nContent truncated for export." : text
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
        return normalized + (bounded.omitted ? "..." : "")
    }

    // MARK: - Per-collection documents

    static func candidate(_ candidate: TestCandidate) -> String {
        document(title: candidate.fullName ?? candidate.email, subtitle: "HackerRank Candidate Report", sections: [
            section("Candidate", [
                ("Name", candidate.fullName), ("Email", candidate.email),
                ("Attempt", candidate.attemptStatusLabel), ("Pipeline", candidate.pipelineStatusLabel),
                ("Score", candidate.score.map { $0.formatted() }),
                ("Percentage", candidate.percentageScore.map { "\($0.formatted())%" }),
                ("Integrity", candidate.integrityStatus),
                ("Plagiarism", candidate.plagiarismStatus.map { $0 ? "Flagged" : "Clear" }),
                ("Started", DisplayFormat.date(candidate.attemptStartTime)),
                ("Ended", DisplayFormat.date(candidate.attemptEndTime))
            ]),
            candidate.hasProctoringSignals ? section("Proctoring", [
                ("Left test window", candidate.outOfWindowEvents.map { "\($0)×" }),
                ("Time outside window", DisplayFormat.interval(candidate.outOfWindowDuration)),
                ("Editor pastes", candidate.editorPasteCount.map { "\($0)×" })
            ]) : "",
            textSection("Tags", candidate.tags.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") }),
            textSection("Feedback", candidate.feedback)
        ])
    }

    static func test(_ test: Test) -> String {
        document(title: test.name, subtitle: "HackerRank Test Report", sections: [
            section("Test", [
                ("State", test.state?.capitalized), ("Unique ID", test.uniqueID),
                ("Duration", test.duration.map { "\($0) min" }),
                ("Cutoff", test.cutoffScore.map(String.init)),
                ("Starts", DisplayFormat.date(test.startTime)), ("Ends", DisplayFormat.date(test.endTime)),
                ("Languages", DisplayFormat.languages(test.languages))
            ]),
            textSection("Tags", test.tags.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") }),
            textSection("Instructions", test.instructions.map(plainText(fromHTML:)))
        ])
    }

    static func question(_ question: Question) -> String {
        document(title: question.name, subtitle: "HackerRank Question Report", sections: [
            section("Question", [
                ("Type", question.type.capitalized), ("Unique ID", question.uniqueID),
                ("Status", question.status?.capitalized),
                ("Max score", question.maxScore.map { $0.formatted() }),
                ("Languages", DisplayFormat.languages(question.languages)),
                ("Skills", DisplayFormat.list(question.skills))
            ]),
            textSection("Problem statement", question.problemStatement.map(plainText(fromHTML:)))
        ])
    }

    static func interview(_ interview: Interview) -> String {
        document(
            title: interview.title ?? "Interview \(interview.id)",
            subtitle: "HackerRank Interview Report",
            sections: [
                section("Interview", [
                    ("Status", interview.status.capitalized),
                    ("Created", DisplayFormat.date(interview.createdAt)),
                    ("Ended", DisplayFormat.date(interview.endedAt)),
                    ("Thumbs up", interview.thumbsUp.map(String.init))
                ]),
                textSection("Notes", interview.notes),
                textSection("Feedback", interview.feedback)
            ]
        )
    }

    // MARK: - Saving

    @MainActor
    static func save(_ markdown: String, suggestedName: String) {
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
    let markdown: () -> String

    var body: some View {
        Button {
            MarkdownExport.save(markdown(), suggestedName: suggestedName)
        } label: {
            Label("Export as Markdown…", systemImage: "doc.plaintext")
        }
        .help("Export as a Markdown file")
    }
}
