//
//  CSVExport.swift
//  rankbuddy-macos
//

import AppKit
import Foundation
import HackerRankKit
import UniformTypeIdentifiers

/// CSV export for the read-only lists (#39) — a recruiter can pull a test's candidates (or
/// any list) into a spreadsheet. The row builders are pure and unit-testable; `save` runs the
/// system save panel (powerbox, so it needs no file entitlement) and writes the file.
enum CSVExport {
    /// Escapes a single CSV field: wrapped in quotes when it contains a comma, quote, or
    /// newline, with embedded quotes doubled (RFC 4180).
    nonisolated static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return value
        }

        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// Joins one row of fields with commas, escaping each.
    nonisolated static func row(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",")
    }

    /// Builds a CSV document from a header and rows.
    static func document(header: [String], rows: [[String]]) -> String {
        ([header] + rows).map(row).joined(separator: "\n")
    }

    // MARK: - Per-collection documents

    static func candidates(_ candidates: [TestCandidate]) -> String {
        document(
            header: ["Name", "Email", "Score", "Percentage", "Attempt", "Pipeline",
                     "Integrity", "Plagiarism", "Started", "Ended", "Tags"],
            rows: candidates.map {
                [$0.fullName ?? "", $0.email,
                 $0.score.map { String($0) } ?? "",
                 $0.percentageScore.map { String($0) } ?? "",
                 $0.attemptStatusLabel ?? "", $0.pipelineStatusLabel ?? "",
                 $0.integrityStatus ?? "",
                 $0.plagiarismStatus.map { $0 ? "Flagged" : "Clear" } ?? "",
                 $0.attemptStartTime ?? "", $0.attemptEndTime ?? "",
                 ($0.tags ?? []).joined(separator: "; ")]
            }
        )
    }

    static func tests(_ tests: [Test]) -> String {
        document(
            header: ["Name", "State", "Unique ID", "Duration (min)", "Cutoff",
                     "Starts", "Ends", "Created", "Languages", "Tags"],
            rows: tests.map {
                [$0.name, $0.state ?? "", $0.uniqueID ?? "",
                 $0.duration.map { String($0) } ?? "",
                 $0.cutoffScore.map { String($0) } ?? "",
                 $0.startTime ?? "", $0.endTime ?? "", $0.createdAt ?? "",
                 ($0.languages ?? []).map(DisplayFormat.languageName).joined(separator: "; "),
                 ($0.tags ?? []).joined(separator: "; ")]
            }
        )
    }

    static func questions(_ questions: [Question]) -> String {
        document(
            header: ["Name", "Type", "Unique ID", "Status", "Max score",
                     "Duration (min)", "Languages", "Skills"],
            rows: questions.map {
                [$0.name, $0.type, $0.uniqueID ?? "", $0.status ?? "",
                 $0.maxScore.map { String($0) } ?? "",
                 $0.recommendedDuration.map { String($0) } ?? "",
                 ($0.languages ?? []).map(DisplayFormat.languageName).joined(separator: "; "),
                 ($0.skills ?? []).joined(separator: "; ")]
            }
        )
    }

    static func interviews(_ interviews: [Interview]) -> String {
        document(
            header: ["Title", "Status", "Created", "Ended", "Thumbs up"],
            rows: interviews.map {
                [$0.title ?? "", $0.status, $0.createdAt ?? "", $0.endedAt ?? "",
                 $0.thumbsUp.map { String($0) } ?? ""]
            }
        )
    }

    // MARK: - Saving

    /// Presents the save panel and writes `csv` to the chosen file. No-op if cancelled.
    @MainActor
    static func save(_ csv: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(suggestedName).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
