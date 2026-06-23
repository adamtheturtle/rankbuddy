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
    }
}
