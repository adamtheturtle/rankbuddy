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
    private static let apiV3 = "/x/api/v3"
    /// Items requested per page. Real accounts have huge collections (≈9.7k questions,
    /// ≈87k interviews), so the read-only lists page through them rather than draining
    /// every page up front (#34).
    private static let pageSize = 50

    private let rest: PaginatedRESTClient
    private let baseURL: URL
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
    /// write flow (#12). The app is read-only by default; this is reached only when the
    /// user has opted into write actions and confirmed the invite.
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

    /// One page of the account's questions, plus the cursor for the next page.
    func questionsPage(after cursor: String? = nil) async throws -> Page<Question> {
        try await page(HackerRankPage<Question>.self, path: "\(Self.apiV3)/questions", cursor: cursor)
    }

    /// One page of the account's interviews, plus the cursor for the next page.
    func interviewsPage(after cursor: String? = nil) async throws -> Page<Interview> {
        try await page(HackerRankPage<Interview>.self, path: "\(Self.apiV3)/interviews", cursor: cursor)
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
        cursor: String?
    ) async throws -> Page<Item> {
        let url = try pageURL(path: path, cursor: cursor)
        let response = try await rest.performWithRetry(HackerRankPage<Item>.self, request: rest.authorizedGET(url))
        return Page(items: response.data, next: response.next)
    }

    /// The absolute `cursor` URL when continuing, or the first-page URL (base + path +
    /// `limit`) when starting.
    private func pageURL(path: String, cursor: String?) throws -> URL {
        if let cursor {
            guard let url = URL(string: cursor) else {
                throw HackerRankError.http(status: 0, body: "Invalid next-page URL.")
            }

            return url
        }

        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: String(Self.pageSize))]
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

/// The body sent when inviting a candidate to a test (#12). Encoded as the API's
/// snake-case JSON; a blank name is omitted entirely rather than sent empty.
private nonisolated struct InviteCandidateRequest: Encodable {
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
