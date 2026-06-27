//
//  Test.swift
//  rankbuddy-macos
//

import Foundation

/// A HackerRank for Work test (assessment).
///
/// Fields mirror the HackerRank for Work API's test resource. Only the fields the
/// read-only UI needs are modelled; `Decodable` ignores any other keys in the
/// response, so this decodes live responses (and the mock fixtures) without
/// failing on unmodelled fields.
///
/// `nonisolated` so the model can be decoded off the main actor by the REST
/// client (the target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
nonisolated struct Test: Codable, Hashable, Identifiable {
    /// The unique identifier of the test.
    let id: String
    /// A short, human-shareable identifier for the test.
    let uniqueID: String?
    /// The test's display name.
    let name: String
    /// ISO-8601 start time of the test window.
    let startTime: String?
    /// ISO-8601 end time of the test window.
    let endTime: String?
    /// Duration of the test in minutes.
    let duration: Int?
    /// Identifier of the user who owns the test.
    let owner: String?
    /// Free-text candidate instructions.
    let instructions: String?
    /// Whether the test is starred by the current user.
    let starred: Bool?
    /// ISO-8601 creation timestamp.
    let createdAt: String?
    /// The lifecycle state of the test (e.g. "active", "archived").
    let state: String?
    /// Whether the test is locked.
    let locked: Bool?
    /// Whether the test is still a draft.
    let draft: Bool?
    /// Programming languages allowed in the test.
    let languages: [String]?
    /// The score at or above which a candidate passes.
    let cutoffScore: Int?
    /// Tags applied to the test.
    let tags: [String]?
    /// Identifiers of the questions in the test.
    let questions: [String]?
    /// Whether question order is shuffled per candidate.
    let shuffleQuestions: Bool?
    /// Whether proctoring is enabled for the test.
    let enableProctoring: Bool?
    /// The test's question sections, when it is organised into them.
    let sections: [TestSection]?

    enum CodingKeys: String, CodingKey {
        case id
        case uniqueID = "unique_id"
        case name
        case startTime = "start_time"
        case endTime = "end_time"
        case duration
        case owner
        case instructions
        case starred
        case createdAt = "created_at"
        case state
        case locked
        case draft
        case languages
        case cutoffScore = "cutoff_score"
        case tags
        case questions
        case shuffleQuestions = "shuffle_questions"
        case enableProctoring = "enable_proctoring"
        case sections
    }
}

/// A named group of questions within a test (the test's `sections`).
///
/// Both `uuid` and `name` are optional: live responses include sections that omit one or
/// both (e.g. an unnamed, ad-hoc section), and a single such section must not fail the whole
/// `Test` (and with it the entire Tests page). `id` falls back through the available fields.
nonisolated struct TestSection: Codable, Hashable, Identifiable {
    /// Stable identifier of the section, when the API provides one.
    let uuid: String?
    /// The section's display name, when set.
    let name: String?
    /// Number of questions in the section.
    let questionCount: Int?
    /// The section's time limit in minutes, if it has its own.
    let duration: Int?

    var id: String {
        uuid ?? name ?? "section"
    }

    /// The name to show, falling back to a generic label when the section is unnamed.
    var displayName: String {
        name ?? "Section"
    }

    enum CodingKeys: String, CodingKey {
        case uuid
        case name
        case questionCount = "questions"
        case duration
    }
}
