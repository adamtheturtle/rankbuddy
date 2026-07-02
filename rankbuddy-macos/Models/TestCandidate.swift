//
//  TestCandidate.swift
//  rankbuddy-macos
//

import BuddyAppKit
import Foundation

/// A candidate associated with a HackerRank for Work test.
///
/// Only the fields the read-only UI needs are modelled; `Decodable` ignores any
/// other keys, so this decodes live responses (and the mock fixtures) without
/// failing on unmodelled fields.
nonisolated struct TestCandidate: Codable, Hashable, Identifiable {
    /// The unique identifier of the candidate record.
    let id: String
    /// The candidate's email address.
    let email: String
    /// The candidate's full name, if known.
    let fullName: String?
    /// The candidate's raw score.
    let score: Double?
    /// The candidate's score as a percentage.
    let percentageScore: Double?
    /// Identifier of the test the candidate took.
    let test: String?
    /// Numeric status code of the candidate's attempt.
    let status: Int?
    /// Applicant-tracking-system state code.
    let atsState: Int?
    /// Integrity (proctoring) status string.
    let integrityStatus: String?
    /// ISO-8601 time the candidate started the attempt.
    let attemptStartTime: String?
    /// ISO-8601 time the candidate finished the attempt.
    let attemptEndTime: String?
    /// Tags applied to the candidate.
    let tags: [String]?
    /// Reviewer feedback, if any.
    let feedback: String?
    /// URL of the candidate's report.
    let reportURL: String?
    /// URL of the candidate's report as a downloadable PDF.
    let pdfURL: String?
    /// Whether plagiarism was flagged.
    let plagiarismStatus: Bool?
    /// Number of times the candidate left the test window (e.g. switched tabs/apps) — a
    /// proctoring signal (#14).
    let outOfWindowEvents: Int?
    /// Total time, in seconds, the candidate spent outside the test window (#14).
    let outOfWindowDuration: Double?
    /// Number of paste actions detected in the code editor — a proctoring signal (#14).
    let editorPasteCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
        case score
        case percentageScore = "percentage_score"
        case test
        case status
        case atsState = "ats_state"
        case integrityStatus = "integrity_status"
        case attemptStartTime = "attempt_starttime"
        case attemptEndTime = "attempt_endtime"
        case tags
        case feedback
        case reportURL = "report_url"
        case pdfURL = "pdf_url"
        case plagiarismStatus = "plagiarism_status"
        case outOfWindowEvents = "out_of_window_events"
        case outOfWindowDuration = "out_of_window_duration"
        case editorPasteCount = "editor_paste_count"
    }
}

extension TestCandidate {
    /// Decodes resiliently. `email` is required in the schema but can be absent or null on live
    /// records (e.g. an invited candidate who hasn't registered); the page decoder drops any
    /// element that throws, so without this those candidates silently vanish from the list (#85).
    /// It defaults to "" so the record still appears. Only `id` is truly required.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = (try? container.decodeIfPresent(String.self, forKey: .email)) ?? ""
        fullName = try? container.decodeIfPresent(String.self, forKey: .fullName)
        score = try? container.decodeIfPresent(Double.self, forKey: .score)
        percentageScore = try? container.decodeIfPresent(Double.self, forKey: .percentageScore)
        test = try? container.decodeIfPresent(String.self, forKey: .test)
        status = try? container.decodeIfPresent(Int.self, forKey: .status)
        atsState = try? container.decodeIfPresent(Int.self, forKey: .atsState)
        integrityStatus = try? container.decodeIfPresent(String.self, forKey: .integrityStatus)
        attemptStartTime = try? container.decodeIfPresent(String.self, forKey: .attemptStartTime)
        attemptEndTime = try? container.decodeIfPresent(String.self, forKey: .attemptEndTime)
        tags = try? container.decodeIfPresent([String].self, forKey: .tags)
        feedback = try? container.decodeIfPresent(String.self, forKey: .feedback)
        reportURL = try? container.decodeIfPresent(String.self, forKey: .reportURL)
        pdfURL = try? container.decodeIfPresent(String.self, forKey: .pdfURL)
        plagiarismStatus = try? container.decodeIfPresent(Bool.self, forKey: .plagiarismStatus)
        outOfWindowEvents = try? container.decodeIfPresent(Int.self, forKey: .outOfWindowEvents)
        outOfWindowDuration = try? container.decodeIfPresent(Double.self, forKey: .outOfWindowDuration)
        editorPasteCount = try? container.decodeIfPresent(Int.self, forKey: .editorPasteCount)
    }
}
