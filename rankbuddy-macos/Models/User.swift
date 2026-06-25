import Foundation

/// A HackerRank for Work user (a member of the organisation).
///
/// A minimal projection: only the fields the read-only UI needs are modelled.
/// `Decodable` ignores any other keys in the response.
nonisolated struct User: Codable, Hashable, Identifiable {
    /// The unique identifier of the user.
    let id: String
    /// The user's email address.
    let email: String
    /// The user's first name.
    let firstName: String?
    /// The user's last name.
    let lastName: String?
    /// The user's country.
    let country: String?
    /// The user's role in the organisation.
    let role: String?
    /// The user's account status.
    let status: String?
    /// Identifiers of the teams the user belongs to.
    let teams: [String]?
    /// Whether the user account is activated.
    let activated: Bool?
    /// Whether the user is a company administrator.
    let companyAdmin: Bool?
    /// Whether the user is a team administrator.
    let teamAdmin: Bool?
    /// ISO-8601 timestamp of the user's last activity, if known.
    let lastActivityTime: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case firstName = "firstname"
        case lastName = "lastname"
        case country
        case role
        case status
        case teams
        case activated
        case companyAdmin = "company_admin"
        case teamAdmin = "team_admin"
        case lastActivityTime = "last_activity_time"
    }
}
