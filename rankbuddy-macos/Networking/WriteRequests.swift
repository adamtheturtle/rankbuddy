import Foundation

// The request bodies and response echoes for `HackerRankClient`'s write flows (#12, #57–#60).
// Extracted from `HackerRankClient.swift` to keep that file within the file-length budget.
// The request types are module-internal (not file-private) so the client can build them; the
// response echoes are all-optional so a 2xx never fails to decode on an unexpected shape.

/// The body sent when inviting a candidate to a test (#12). Encoded as the API's
/// snake-case JSON; a blank name is omitted entirely rather than sent empty.
nonisolated struct InviteCandidateRequest: Encodable {
    let email: String
    let fullName: String?
    let sendEmail: Bool

    enum CodingKeys: String, CodingKey {
        case email
        case fullName = "full_name"
        case sendEmail = "send_email"
    }
}

/// The candidate record echoed back by a successful invite. Every field is optional so a
/// 2xx response never fails to decode on an unexpected shape — the invite is what matters,
/// not parsing the echo.
nonisolated struct InvitedCandidate: Decodable {
    let id: String?
    let email: String?
}

/// The body sent when creating a user (#58). Snake-case to match the API; blank optional
/// fields are omitted.
nonisolated struct CreateUserRequest: Encodable {
    let email: String
    let firstName: String?
    let lastName: String?
    let role: String?

    enum CodingKeys: String, CodingKey {
        case email
        case firstName = "firstname"
        case lastName = "lastname"
        case role
    }
}

/// The user record echoed back by a successful create. All-optional so a 2xx never fails to
/// decode on an unexpected shape.
nonisolated struct CreatedUser: Decodable {
    let id: String?
    let email: String?
}

/// The body sent when creating a test (#57).
nonisolated struct CreateTestRequest: Encodable {
    let name: String
}

/// The body sent when renaming a test (#57).
nonisolated struct UpdateTestRequest: Encodable {
    let name: String
}

/// The test echoed back by a successful create/update/delete (#57). All-optional so a 2xx
/// never fails to decode on an unexpected shape.
nonisolated struct CreatedTest: Decodable {
    let id: String?
    let name: String?
}

/// The body sent when creating a team (#59).
nonisolated struct CreateTeamRequest: Encodable {
    let name: String
}

/// The body sent when adding a team member (#59). Snake-case to match the API; a blank role
/// is omitted.
nonisolated struct AddTeamMemberRequest: Encodable {
    let email: String
    let role: String?
}

/// An empty JSON body (`{}`) for a write whose parameters are all in the path — a team-member
/// removal identifies the user in the URL.
nonisolated struct EmptyBody: Encodable {}

/// The team echoed back by a successful create (#59). All-optional so a 2xx never fails to
/// decode on an unexpected shape.
nonisolated struct CreatedTeam: Decodable {
    let id: String?
    let name: String?
}

/// The record echoed back by a team-membership change (#59). All-optional for the same
/// reason as the other write echoes.
nonisolated struct TeamMembershipResult: Decodable {
    let id: String?
    let email: String?
}

/// The body sent when creating a QuickPad interview (#60).
nonisolated struct CreateQuickPadRequest: Encodable {
    let title: String?
    let quickpad: Bool
}

/// The body sent when scheduling an interview (#60). The start time is an ISO-8601 string;
/// blank optional fields are omitted.
nonisolated struct ScheduleInterviewRequest: Encodable {
    let title: String
    let from: String
    let candidate: String?
    let notes: String?
}

/// The interview echoed back by a successful create (#60). All-optional so a 2xx never fails
/// to decode on an unexpected shape; the URL lets the UI open the new pad.
nonisolated struct CreatedInterview: Decodable {
    let id: String?
    let url: String?
    let status: String?
}
