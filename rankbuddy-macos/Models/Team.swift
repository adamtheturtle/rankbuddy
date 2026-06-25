import Foundation

/// A HackerRank for Work team.
///
/// A minimal projection: only the fields the read-only UI needs are modelled.
/// `Decodable` ignores any other keys in the response.
nonisolated struct Team: Codable, Hashable, Identifiable {
    /// The unique identifier of the team.
    let id: String
    /// The team's display name.
    let name: String
    /// Identifier of the user who owns the team.
    let owner: String?
    /// ISO-8601 creation timestamp.
    let createdAt: String?
    /// Number of recruiters on the team.
    let recruiterCount: Int?
    /// Number of developers on the team.
    let developerCount: Int?
    /// Number of interviewers on the team.
    let interviewerCount: Int?
    /// Office locations associated with the team.
    let locations: [String]?
    /// Departments associated with the team.
    let departments: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case owner
        case createdAt = "created_at"
        case recruiterCount = "recruiter_count"
        case developerCount = "developer_count"
        case interviewerCount = "interviewer_count"
        case locations
        case departments
    }
}
