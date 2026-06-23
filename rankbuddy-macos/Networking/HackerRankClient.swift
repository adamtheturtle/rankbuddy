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

    private let rest: PaginatedRESTClient
    private let baseURL: URL
    private let token: String

    init(account: Account, session: URLSession = .shared) {
        baseURL = account.baseURL
        token = account.token
        let logger = Logger(subsystem: "com.adamdangoor.rankbuddy", category: "client")
        rest = PaginatedRESTClient(
            apiKey: account.token,
            baseURL: account.baseURL,
            session: session,
            decoderFactory: { JSONDecoder() },
            encoderFactory: { JSONEncoder() },
            errors: HackerRankErrorMapping(),
            logger: logger
        )
    }

    /// All tests in the account, across every page.
    func tests() async throws -> [Test] {
        try await rest.fetchAllPages(HackerRankPage<Test>.self, path: "\(Self.apiV3)/tests")
    }

    /// All candidates for a given test, across every page.
    func candidates(testID: String) async throws -> [TestCandidate] {
        try await rest.fetchAllPages(
            HackerRankPage<TestCandidate>.self,
            path: "\(Self.apiV3)/tests/\(testID)/candidates"
        )
    }

    /// All questions in the account, across every page.
    func questions() async throws -> [Question] {
        try await rest.fetchAllPages(HackerRankPage<Question>.self, path: "\(Self.apiV3)/questions")
    }

    /// All interviews in the account, across every page.
    func interviews() async throws -> [Interview] {
        try await rest.fetchAllPages(HackerRankPage<Interview>.self, path: "\(Self.apiV3)/interviews")
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
}
