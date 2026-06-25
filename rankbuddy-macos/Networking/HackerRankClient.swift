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
