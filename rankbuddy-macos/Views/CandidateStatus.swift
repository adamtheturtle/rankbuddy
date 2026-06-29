//
//  CandidateStatus.swift
//  rankbuddy-macos
//

import Foundation

/// Human-readable labels for the candidate `status` (test-attempt state) and `ats_state`
/// (recruitment-pipeline position) integer codes (#37).
///
/// The codes follow HackerRank's documented values
/// (support.hackerrank.com/hc/en-us/articles/219993708). Only the stable, unambiguous codes
/// are mapped; transient intermediate states, the "not set" value, and any unknown code map
/// to `nil` so the UI simply omits the row rather than showing a misleading guess. The exact
/// table is worth confirming against a live account (the same API-contract unknown as #3).
extension TestCandidate {
    /// A label for the `status` (attempt) code, or `nil` for transient/unknown states.
    var attemptStatusLabel: String? {
        switch status {
        case -1: "Invited"
        case 0: "In progress"
        case 1: "Completed (reports pending)"
        case 7: "Reports ready"
        default: nil
        }
    }

    /// Whether any proctoring signal is present and non-zero, so the detail view can show a
    /// Proctoring section only when there is something to report (#14).
    var hasProctoringSignals: Bool {
        (outOfWindowEvents ?? 0) > 0 || (outOfWindowDuration ?? 0) > 0 || (editorPasteCount ?? 0) > 0
    }

    /// The most decision-relevant status for a compact summary: the pipeline state when
    /// set, otherwise the attempt state. `nil` when neither has a known label.
    var listStatusLabel: String? {
        pipelineStatusLabel ?? attemptStatusLabel
    }

    /// A label for the `ats_state` (pipeline) code, or `nil` when unset/unknown.
    var pipelineStatusLabel: String? {
        switch atsState {
        case 1: "Test completed: evaluation required"
        case 2: "Test completed: qualified"
        case 3: "Test completed: failed"
        case 7: "Offer sent"
        case 8: "Offer negotiation"
        case 9: "Offer accepted"
        case 10: "Offer declined"
        case 11: "On hold"
        case 12: "Phone interview: cleared"
        case 13: "Phone interview: failed"
        case 14: "Technical interview: cleared"
        case 15: "Technical interview: failed"
        case 16: "HR interview: cleared"
        case 17: "HR interview: failed"
        case 21: "Hired"
        case 22: "Rejected"
        default: nil
        }
    }
}
