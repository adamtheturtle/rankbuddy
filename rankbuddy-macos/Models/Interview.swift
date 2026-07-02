//
//  Interview.swift
//  rankbuddy-macos
//

import BuddyAppKit
import Foundation

/// A HackerRank for Work interview.
///
/// Only the fields the read-only UI needs are modelled; `Decodable` ignores any
/// other keys, so this decodes live responses (and the mock fixtures) without
/// failing on unmodelled fields.
nonisolated struct Interview: Codable, Hashable, Identifiable {
    /// The unique identifier of the interview.
    let id: String
    /// The lifecycle status of the interview.
    let status: String
    /// The interview's web URL.
    let url: String
    /// The interview's display title, if any.
    let title: String?
    /// Reviewer feedback, if any.
    let feedback: String?
    /// A thumbs-up rating, if any.
    let thumbsUp: Int?
    /// Free-text notes.
    let notes: String?
    /// ISO-8601 creation timestamp.
    let createdAt: String?
    /// ISO-8601 last-updated timestamp.
    let updatedAt: String?
    /// ISO-8601 time the interview ended.
    let endedAt: String?
    /// Identifier of the interview template used.
    let interviewTemplateID: Int?
    /// URL of the interview's report, if any.
    let reportURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case url
        case title
        case feedback
        case thumbsUp = "thumbs_up"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case endedAt = "ended_at"
        case interviewTemplateID = "interview_template_id"
        case reportURL = "report_url"
    }
}

extension Interview {
    /// Decodes resiliently. `status` and `url` are required in the schema but can be absent or
    /// null on live records (e.g. a freshly scheduled interview with no URL yet); the page
    /// decoder drops any element that throws, so without this those interviews silently vanish
    /// from the list (#85). They default to "" so the record still appears. Only `id` is truly
    /// required — an interview with no identity can't be shown.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        status = container.lenientDecodeIfPresent(String.self, forKey: .status) ?? ""
        url = container.lenientDecodeIfPresent(String.self, forKey: .url) ?? ""
        title = container.lenientDecodeIfPresent(String.self, forKey: .title)
        feedback = container.lenientDecodeIfPresent(String.self, forKey: .feedback)
        thumbsUp = container.lenientDecodeIfPresent(Int.self, forKey: .thumbsUp)
        notes = container.lenientDecodeIfPresent(String.self, forKey: .notes)
        createdAt = container.lenientDecodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = container.lenientDecodeIfPresent(String.self, forKey: .updatedAt)
        endedAt = container.lenientDecodeIfPresent(String.self, forKey: .endedAt)
        interviewTemplateID = container.lenientDecodeIfPresent(Int.self, forKey: .interviewTemplateID)
        reportURL = container.lenientDecodeIfPresent(String.self, forKey: .reportURL)
    }
}
