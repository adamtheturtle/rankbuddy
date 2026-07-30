//
//  CandidateSummary.swift
//  rankbuddy-macos
//

#if canImport(FoundationModels) && arch(arm64)
    import FoundationModels
#endif
import HackerRankKit
import SwiftUI

/// Assembles the factual brief that feeds the on-device candidate summary (#93).
///
/// Pure, deterministic, and unit-tested: it turns the fields RankBuddy already shows on a
/// candidate into a list of neutral signal statements. Deliberately excludes the candidate's
/// name, email, and free-form reviewer feedback — the summary is about allowlisted performance
/// signals, not identity — so arbitrary identifying detail is never put in the prompt.
enum CandidateBrief {
    /// The neutral signal statements for a candidate, in reading order. Empty when there is
    /// nothing substantive to summarise (e.g. an invited-but-not-attempted candidate).
    static func facts(for candidate: TestCandidate) -> [String] {
        var facts: [String] = []

        if let score = candidate.score {
            if let percentage = candidate.percentageScore {
                facts.append("Score: \(score.formatted()) (\(percentage.formatted())%)")
            } else {
                facts.append("Score: \(score.formatted())")
            }
        }
        if let attempt = candidate.attemptStatusLabel {
            facts.append("Attempt status: \(attempt)")
        }
        if let pipeline = candidate.pipelineStatusLabel {
            facts.append("Pipeline status: \(pipeline)")
        }
        if let integrity = candidate.integrityStatus, !integrity.isEmpty {
            facts.append("Integrity check: \(integrity)")
        }
        if let plagiarism = candidate.plagiarismStatus {
            facts.append(plagiarism ? "Plagiarism: flagged" : "Plagiarism: clear")
        }
        facts.append(contentsOf: proctoringFacts(for: candidate))
        return facts
    }

    private static func proctoringFacts(for candidate: TestCandidate) -> [String] {
        guard candidate.hasProctoringSignals else { return [] }

        var facts: [String] = []
        if let events = candidate.outOfWindowEvents, events > 0 {
            facts.append("Left the test window \(events) time\(events == 1 ? "" : "s")")
        }
        if let duration = candidate.outOfWindowDuration, duration > 0,
           let interval = DisplayFormat.interval(duration) {
            facts.append("Time spent outside the test window: \(interval)")
        }
        if let pastes = candidate.editorPasteCount, pastes > 0 {
            facts.append("Editor pastes: \(pastes)")
        }
        return facts
    }

    /// The full prompt for the model, or `nil` when there are no facts worth summarising.
    static func prompt(for candidate: TestCandidate) -> String? {
        let facts = facts(for: candidate)
        guard !facts.isEmpty else { return nil }

        let signals = facts.map { "- \($0)" }.joined(separator: "\n")
        return """
        Summarise this coding-test candidate's results in 2–3 short, plain-language sentences \
        for a hiring reviewer. Describe only what the signals below show; do not invent details \
        and do not give a hire / no-hire recommendation.

        Signals:
        \(signals)
        """
    }
}

nonisolated enum CandidateSummaryPolicy {
    private static let prohibitedPatterns = [
        #"\b(recommend|recommends|recommended|recommendation)\b"#,
        #"\b(no[ -]?hire|hire|hired|hiring)\b"#,
        #"\b(reject|rejects|rejected|rejection)\b"#,
        #"\b(advance|advanced|proceed|progress)\b"#,
        #"\b(move|moving)\s+forward\b"#,
        #"\b(good|poor|strong|weak)\s+(candidate|fit)\b"#,
        #"\b(suitable|unsuitable|worthy|unworthy)\b"#
    ]

    static func allows(_ summary: String) -> Bool {
        !prohibitedPatterns.contains {
            summary.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}

/// The on-device summariser for a candidate report (#93). Strictly opt-in (never auto-runs),
/// nothing persisted, and a graceful no-op when Apple's on-device model is unavailable.
@MainActor
enum CandidateSummarizer {
    /// Whether the on-device model is ready, so the UI can hide the affordance otherwise.
    static var isAvailable: Bool {
        #if canImport(FoundationModels) && arch(arm64)
            if #available(macOS 26, *) {
                return SystemLanguageModel.default.isAvailable
            }
        #endif
        return false
    }

    /// The instructions that set the model's tone and guardrails for every summary.
    private static let instructions = """
    You are a concise, neutral assistant that summarises coding-test candidate results for \
    hiring reviewers. Keep summaries factual and brief. Never invent information that is not in \
    the provided signals, and never state a hiring decision.
    """

    /// The outcome of a summary request, so the view can show the right state without throwing.
    enum Outcome: Equatable {
        case summary(String)
        case noData
        case unavailable
        case policyViolation
        case failed
    }

    /// Produces a plain-language summary for the candidate, or a non-throwing outcome describing
    /// why it couldn't. On-device only; the candidate's text never leaves the device.
    static func summarize(_ candidate: TestCandidate) async -> Outcome {
        guard isAvailable else { return .unavailable }
        guard let prompt = CandidateBrief.prompt(for: candidate) else { return .noData }

        #if canImport(FoundationModels) && arch(arm64)
            if #available(macOS 26, *) {
                let session = LanguageModelSession(instructions: instructions)
                do {
                    let response = try await session.respond(to: prompt)
                    let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return .failed }
                    guard CandidateSummaryPolicy.allows(text) else { return .policyViolation }

                    return .summary(text)
                } catch {
                    return .failed
                }
            }
        #endif
        return .unavailable
    }
}
