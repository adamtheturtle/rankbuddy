//
//  HackerRankClient.swift
//  rankbuddy-macos
//

import Foundation
import os
import PaginatedRESTClient

/// A read-only client for the HackerRank for Work API, composed over the generic
/// `PaginatedRESTClient` transport.
///
/// Endpoints are the documented v3 API (`/x/api/v3/...`) with Bearer-token auth.
/// Pagination, retry/backoff, `429` handling, and cancellation are provided by the
/// transport; this type adds the HackerRank base URL, endpoint paths, and the paged
/// envelope. MainActor-isolated (like the transport's high-level API); the expensive
/// page fetching and JSON decoding still run off the main actor inside the transport.
struct HackerRankClient {
    /// Internal (not private) so the parallel `allUsers` loader in `HackerRankClient+AllUsers`
    /// can build offset requests against the same transport, per the repo's split-file rule (#86).
    static let apiV3 = "/x/api/v3"
    /// Items requested per page — the API's maximum (requests above 100 are rejected). Real
    /// accounts have huge collections (≈9.7k questions, ≈87k interviews), so the read-only lists
    /// page through them rather than draining every page up front (#34); the larger page also
    /// halves the request count when search pages through a big list to find a match (#86).
    static let pageSize = 100

    let rest: PaginatedRESTClient
    let baseURL: URL
    private let token: String

    /// - Parameter session: the transport session. Defaults to the demo mock for `isMock`
    ///   accounts and the shared session otherwise; tests can inject an explicit session.
    init(account: Account, session: URLSession? = nil) {
        let session = session ?? (account.isMock ? .rankBuddyDemo : .shared)
        baseURL = account.baseURL
        token = account.token
        let logger = Logger(subsystem: "com.adamdangoor.rankbuddy", category: "client")
        rest = PaginatedRESTClient(
            apiKey: account.token,
            baseURL: account.baseURL,
            transport: URLSessionTransport(session: session),
            decoderFactory: { JSONDecoder() },
            encoderFactory: { JSONEncoder() },
            errors: HackerRankErrorMapping(),
            log: { logger.log("\($0)") }
        )
    }

    /// One page of the account's tests, plus the cursor for the next page.
    func testsPage(after cursor: String? = nil) async throws -> Page<Test> {
        try await page(HackerRankPage<Test>.self, path: "\(Self.apiV3)/tests", cursor: cursor)
    }

    /// One page of a test's candidates, plus the cursor for the next page.
    func candidatesPage(testID: String, after cursor: String? = nil) async throws -> Page<TestCandidate> {
        try await page(
            HackerRankPage<TestCandidate>.self,
            path: "\(Self.apiV3)/tests/\(Self.pathSegment(testID))/candidates",
            cursor: cursor
        )
    }

    /// Invites a candidate to a test (`POST /tests/{id}/candidates`) — the app's first
    /// write flow (#12). The user confirms the invite before it runs.
    ///
    /// - Parameters:
    ///   - testID: the test to invite the candidate to.
    ///   - email: the candidate's email address (the only required field).
    ///   - fullName: the candidate's name, if known; blank names are sent as absent.
    ///   - sendEmail: whether HackerRank should email the candidate the invitation.
    /// - Returns: the created candidate as echoed by the API (fields are optional, so a 2xx
    ///   never fails on an unexpected response shape).
    @discardableResult
    func inviteCandidate(
        testID: String,
        email: String,
        fullName: String? = nil,
        sendEmail: Bool = true
    ) async throws -> InvitedCandidate {
        let trimmedName = fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = InviteCandidateRequest(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            fullName: (trimmedName?.isEmpty == false) ? trimmedName : nil,
            sendEmail: sendEmail
        )
        return try await rest.send(
            InvitedCandidate.self,
            method: "POST",
            path: "\(Self.apiV3)/tests/\(Self.pathSegment(testID))/candidates",
            body: body
        )
    }

    /// Creates a test (`POST /tests`) (#57).
    ///
    /// - Returns: the created test as echoed by the API (all-optional, so a 2xx never fails to
    ///   decode on an unexpected shape).
    @discardableResult
    func createTest(name: String) async throws -> CreatedTest {
        let body = CreateTestRequest(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        return try await rest.send(CreatedTest.self, method: "POST", path: "\(Self.apiV3)/tests", body: body)
    }

    /// Renames a test (`PATCH /tests/{id}`) (#57).
    @discardableResult
    func updateTest(testID: String, name: String) async throws -> CreatedTest {
        let body = UpdateTestRequest(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        return try await rest.send(
            CreatedTest.self,
            method: "PATCH",
            path: "\(Self.apiV3)/tests/\(Self.pathSegment(testID))",
            body: body
        )
    }

    /// Permanently deletes a test (`DELETE /tests/{id}`) (#57). Destructive and irreversible,
    /// so the UI confirms (naming the test) before this is called. The test is identified in
    /// the path, so the request carries an empty JSON body.
    @discardableResult
    func deleteTest(testID: String) async throws -> CreatedTest {
        try await rest.send(
            CreatedTest.self,
            method: "DELETE",
            path: "\(Self.apiV3)/tests/\(Self.pathSegment(testID))",
            body: EmptyBody()
        )
    }

    /// Creates an organisation user (`POST /users`) (#58). Like the invite flow (#12), the
    /// user confirms before it runs.
    ///
    /// - Returns: the created user as echoed by the API (fields are optional, so a 2xx never
    ///   fails on an unexpected response shape).
    @discardableResult
    func createUser(
        email: String,
        firstName: String? = nil,
        lastName: String? = nil,
        role: String? = nil
    ) async throws -> CreatedUser {
        func trimmed(_ value: String?) -> String? {
            let result = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (result?.isEmpty == false) ? result : nil
        }

        let body = CreateUserRequest(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            firstName: trimmed(firstName),
            lastName: trimmed(lastName),
            role: trimmed(role)
        )
        return try await rest.send(CreatedUser.self, method: "POST", path: "\(Self.apiV3)/users", body: body)
    }

    /// Creates a team (`POST /teams`) (#59).
    ///
    /// - Returns: the created team as echoed by the API (all-optional, so a 2xx never fails
    ///   to decode on an unexpected shape).
    @discardableResult
    func createTeam(name: String) async throws -> CreatedTeam {
        let body = CreateTeamRequest(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        return try await rest.send(CreatedTeam.self, method: "POST", path: "\(Self.apiV3)/teams", body: body)
    }

    /// Adds a member to a team (`POST /teams/{id}/users`) (#59).
    @discardableResult
    func addTeamMember(teamID: String, email: String, role: String? = nil) async throws -> TeamMembershipResult {
        let trimmedRole = role?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = AddTeamMemberRequest(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            role: (trimmedRole?.isEmpty == false) ? trimmedRole : nil
        )
        return try await rest.send(
            TeamMembershipResult.self,
            method: "POST",
            path: "\(Self.apiV3)/teams/\(Self.pathSegment(teamID))/users",
            body: body
        )
    }

    /// Removes a member from a team (`DELETE /teams/{id}/users/{userID}`) (#59). Destructive,
    /// so the UI confirms before this is called. The user is identified in the path, so the
    /// request carries an empty JSON body.
    @discardableResult
    func removeTeamMember(teamID: String, userID: String) async throws -> TeamMembershipResult {
        try await rest.send(
            TeamMembershipResult.self,
            method: "DELETE",
            path: "\(Self.apiV3)/teams/\(Self.pathSegment(teamID))/users/\(Self.pathSegment(userID))",
            body: EmptyBody()
        )
    }

    /// Creates an instant QuickPad collaborative interview (`POST /interviews`) (#60).
    ///
    /// - Returns: the created interview as echoed by the API (all-optional, so a 2xx never
    ///   fails to decode on an unexpected shape).
    @discardableResult
    func createQuickPad(title: String? = nil) async throws -> CreatedInterview {
        // The API rejects a titleless interview with HTTP 400 (#83). The QuickPad form treats
        // the title as optional, so fall back to a dated default rather than surfacing an error.
        let body = CreateQuickPadRequest(title: Self.nonBlank(title) ?? Self.defaultQuickPadTitle(), quickpad: true)
        return try await rest.send(
            CreatedInterview.self,
            method: "POST",
            path: "\(Self.apiV3)/interviews",
            body: body
        )
    }

    /// Schedules an interview (`POST /interviews`) (#60). The start time is sent as an
    /// ISO-8601 timestamp.
    @discardableResult
    func scheduleInterview(
        title: String,
        from: Date,
        candidateEmail: String? = nil,
        notes: String? = nil
    ) async throws -> CreatedInterview {
        let body = ScheduleInterviewRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            from: ISO8601DateFormatter().string(from: from),
            candidate: Self.nonBlank(candidateEmail),
            notes: Self.nonBlank(notes)
        )
        return try await rest.send(
            CreatedInterview.self,
            method: "POST",
            path: "\(Self.apiV3)/interviews",
            body: body
        )
    }

    /// One page of the account's questions, plus the cursor for the next page.
    func questionsPage(after cursor: String? = nil) async throws -> Page<Question> {
        try await page(HackerRankPage<Question>.self, path: "\(Self.apiV3)/questions", cursor: cursor)
    }

    /// One page of the account's interviews, plus the cursor for the next page.
    ///
    /// Requests **newest-first** ordering from the server (`order_by=created_at&order_dir=desc`).
    /// Real accounts have huge interview collections (≈87k) returned oldest-first by default, so
    /// without this the first pages — the only ones a user realistically scrolls — are the oldest
    /// interviews, and the recent ones (incl. anything created today) never load (#85). The exact
    /// parameter names are from the HackerRank for Work OpenAPI spec for `GET /interviews`:
    /// `order_by` ∈ {title, id, created_at, ended_at, current_status, user} and `order_dir` ∈
    /// {asc, desc}, where `order_dir` is required whenever `order_by` is set. The server carries
    /// the ordering into the `next` URLs, so subsequent pages inherit it.
    ///
    /// `createdAtRange` (a `created_at=<from>..<to>` value, see `DateRangeFilter`) filters by
    /// creation date **server-side** when a date range is active (#86), so the date chip works
    /// across all 87k interviews rather than only the loaded rows. It's ignored on follow-up
    /// pages (the absolute `next` cursor already carries every query parameter).
    func interviewsPage(after cursor: String? = nil, createdAtRange: String? = nil) async throws -> Page<Interview> {
        var query = [
            URLQueryItem(name: "order_by", value: "created_at"),
            URLQueryItem(name: "order_dir", value: "desc")
        ]
        if let createdAtRange {
            query.append(URLQueryItem(name: "created_at", value: createdAtRange))
        }
        return try await page(
            HackerRankPage<Interview>.self,
            path: "\(Self.apiV3)/interviews",
            cursor: cursor,
            query: query
        )
    }

    /// One page of the organisation's users (members), plus the cursor for the next page.
    func usersPage(after cursor: String? = nil) async throws -> Page<User> {
        try await page(HackerRankPage<User>.self, path: "\(Self.apiV3)/users", cursor: cursor)
    }

    /// One page of the organisation's teams, plus the cursor for the next page.
    func teamsPage(after cursor: String? = nil) async throws -> Page<Team> {
        try await page(HackerRankPage<Team>.self, path: "\(Self.apiV3)/teams", cursor: cursor)
    }

    /// One page of a team's members (users), plus the cursor for the next page (#56).
    func teamMembersPage(teamID: String, after cursor: String? = nil) async throws -> Page<User> {
        try await page(
            HackerRankPage<User>.self,
            path: "\(Self.apiV3)/teams/\(Self.pathSegment(teamID))/users",
            cursor: cursor
        )
    }

    /// Fetches a single page: the first page (with an explicit page size) when `cursor` is
    /// `nil`, or the page at the given absolute `next` cursor URL otherwise.
    private func page<Item: Decodable & Sendable>(
        _: HackerRankPage<Item>.Type,
        path: String,
        cursor: String?,
        query: [URLQueryItem] = []
    ) async throws -> Page<Item> {
        let url = try pageURL(path: path, cursor: cursor, query: query)
        let response = try await rest.performWithRetry(HackerRankPage<Item>.self, request: rest.authorizedGET(url))
        return Page(items: response.data, next: response.next)
    }

    /// The absolute `cursor` URL when continuing, or the first-page URL (base + path +
    /// `limit`, plus any endpoint-specific `query` such as ordering) when starting. Subsequent
    /// pages reuse the absolute `next` URL, which already carries the original query.
    private func pageURL(path: String, cursor: String?, query: [URLQueryItem] = []) throws -> URL {
        if let cursor {
            guard let url = URL(string: cursor) else {
                throw HackerRankError.http(status: 0, body: "Invalid next-page URL.")
            }

            return url
        }

        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: String(Self.pageSize))] + query
        guard let url = components?.url else {
            throw HackerRankError.http(status: 0, body: "Could not build the page URL.")
        }

        return url
    }

    /// Lightweight token validation: requests a single test. A 2xx response (even with no
    /// tests) means the token authenticates; an auth failure throws `HackerRankError.http`
    /// with a 401/403 status. Throws before any request when the token is empty.
    func validateToken() async throws {
        guard !token.isEmpty else { throw HackerRankError.missingAPIKey }

        var components = URLComponents(
            url: baseURL.appending(path: "\(Self.apiV3)/tests"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "limit", value: "1")]
        guard let url = components?.url else {
            throw HackerRankError.http(status: 0, body: "Could not build the validation URL.")
        }

        _ = try await rest.performWithRetry(HackerRankPage<Test>.self, request: rest.authorizedGET(url))
    }

    /// The user the token belongs to (`GET /users/me`). Used to auto-discover an account's
    /// identity (#72) so "who am I" is captured without hand-entry. The endpoint returns a
    /// single user object (not a paged envelope), in the same shape as the People list, so it
    /// decodes straight into `User`.
    func currentUser() async throws -> User {
        let url = baseURL.appending(path: "\(Self.apiV3)/users/me")
        return try await rest.performWithRetry(User.self, request: rest.authorizedGET(url))
    }

    /// Trims `value` and returns `nil` for an empty/whitespace-only result, so blank optional
    /// fields are omitted from a write body rather than sent empty.
    private static func nonBlank(_ value: String?) -> String? {
        let result = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (result?.isEmpty == false) ? result : nil
    }

    /// A dated fallback title for a QuickPad created without one (#83), so the optional title
    /// stays optional in the UI while the API still receives the title it requires.
    private static func defaultQuickPadTitle() -> String {
        "QuickPad — \(Date.now.formatted(date: .abbreviated, time: .shortened))"
    }

    private static func pathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// One page of a list endpoint: the decoded items plus the cursor (absolute `next` URL)
/// for the following page, or `nil` on the last page.
nonisolated struct Page<Item: Sendable> {
    let items: [Item]
    let next: String?
}
