//
//  User.swift
//  rankbuddy-macos
//

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

extension User {
    /// Decodes resiliently. `email` is required in the schema but can be absent or null on live
    /// records (SSO members, pending invites, service accounts); the page decoder drops any
    /// element that throws, so without this those users silently vanish from the People list
    /// (#85). It defaults to "" so the record still appears. Only `id` is truly required.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = container.lenient(String.self, .email) ?? ""
        firstName = container.lenient(String.self, .firstName)
        lastName = container.lenient(String.self, .lastName)
        country = container.lenient(String.self, .country)
        role = container.lenient(String.self, .role)
        status = container.lenient(String.self, .status)
        teams = container.lenient([String].self, .teams)
        activated = container.lenient(Bool.self, .activated)
        companyAdmin = container.lenient(Bool.self, .companyAdmin)
        teamAdmin = container.lenient(Bool.self, .teamAdmin)
        lastActivityTime = container.lenient(String.self, .lastActivityTime)
    }
}
