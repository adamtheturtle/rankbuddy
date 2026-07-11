//
//  HackerRankClient+CreateUserTeams.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit

/// The server requires a `teams` parameter on `POST /users` (it rejects a create with
/// HTTP 400 "Parameter teams is required"), but HackerRankKit 0.2.1's `createUser` cannot
/// send one. This builds the request directly with the client's own session and
/// credentials, so it behaves identically for real and demo (mock) accounts. Delete this
/// file once the Kit's `createUser` gains a `teams` argument.
extension HackerRankClient {
    /// Creates an organisation user assigned to the given teams (`POST /users`).
    /// Blank optional fields are omitted, matching the Kit's own write requests.
    @discardableResult
    func createUser(
        email: String,
        firstName: String,
        lastName: String?,
        role: String,
        teamIDs: [String]
    ) async throws -> CreatedUser? {
        guard !token.isEmpty else { throw HackerRankError.missingAPIKey }

        let trimmedLast = lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body = CreateUserWithTeamsRequest(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            firstname: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastname: trimmedLast.isEmpty ? nil : trimmedLast,
            role: role,
            teams: teamIDs.map(CreateUserWithTeamsRequest.TeamRef.init)
        )

        var request = URLRequest(url: baseURL.appending(path: "/x/api/v3/users"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw HackerRankError.network(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ... 299).contains(status) else {
            throw HackerRankError.http(status, String(bytes: data, encoding: .utf8) ?? "")
        }
        // The create is what matters, not parsing the echo; a 2xx with an unexpected
        // shape just yields nil, mirroring the Kit's all-optional `CreatedUser`.
        return try? Self.makeDecoder().decode(CreatedUser.self, from: data)
    }
}

/// The body for a user create that assigns teams. Snake-case field names match the API;
/// a blank last name is omitted.
private nonisolated struct CreateUserWithTeamsRequest: Encodable {
    let email: String
    let firstname: String
    let lastname: String?
    let role: String
    let teams: [TeamRef]

    /// The API's team reference shape: an object holding the team's id.
    struct TeamRef: Encodable {
        let id: String
    }
}
