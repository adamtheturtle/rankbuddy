//
//  Question.swift
//  rankbuddy-macos
//

import Foundation

/// A HackerRank for Work question.
///
/// Only the fields the read-only UI needs are modelled; `Decodable` ignores any
/// other keys, so this decodes live responses (and the mock fixtures) without
/// failing on unmodelled fields.
nonisolated struct Question: Codable, Hashable, Identifiable {
    /// The unique identifier of the question.
    let id: String
    /// A short, human-shareable identifier for the question.
    let uniqueID: String?
    /// The question type (e.g. "code", "mcq").
    let type: String
    /// The question's display name.
    let name: String
    /// Identifier of the user who owns the question.
    let owner: String?
    /// ISO-8601 creation timestamp.
    let createdAt: String?
    /// The lifecycle status of the question.
    let status: String?
    /// Programming languages allowed for the question.
    let languages: [String]?
    /// The problem statement, typically Markdown or HTML.
    let problemStatement: String?
    /// Recommended solving time in minutes.
    let recommendedDuration: Int?
    /// Tags applied to the question.
    let tags: [String]?
    /// The maximum achievable score.
    let maxScore: Double?
    /// Skills the question assesses.
    let skills: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case uniqueID = "unique_id"
        case type
        case name
        case owner
        case createdAt = "created_at"
        case status
        case languages
        case problemStatement = "problem_statement"
        case recommendedDuration = "recommended_duration"
        case tags
        case maxScore = "max_score"
        case skills
    }
}
