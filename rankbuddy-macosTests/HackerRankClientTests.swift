//
//  HackerRankClientTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Synchronization
import Testing

/// Fails the first two GETs with a retryable status, then returns a valid tests page.
/// The mutex keeps the request count safe when URLSession invokes the protocol on its
/// own worker queue.
private final class TransientThenSuccessURLProtocol: URLProtocol {
    private static let requestCounter = Mutex(0)

    static func reset() {
        requestCounter.withLock { $0 = 0 }
    }

    static var requestCount: Int {
        requestCounter.withLock { $0 }
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let attempt = Self.requestCounter.withLock {
            $0 += 1
            return $0
        }
        let status = attempt < 3 ? 429 : 200
        let body = attempt < 3
            ? Data(#"{"message":"Please retry"}"#.utf8)
            : Data(#"{"data":[{"id":"retried","name":"Recovered"}],"next":null}"#.utf8)
        let headers = attempt < 3 ? ["Retry-After": "0"] : ["Content-Type": "application/json"]
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: status,
                  httpVersion: "HTTP/1.1",
                  headerFields: headers
              )
        else { return }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Holds a request open until its task is cancelled, allowing the client integration
/// suite to prove cancellation does not enter the transient retry loop.
private final class HangingURLProtocol: URLProtocol {
    private static let requestCounter = Mutex(0)

    static func reset() {
        requestCounter.withLock { $0 = 0 }
    }

    static var requestCount: Int {
        requestCounter.withLock { $0 }
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCounter.withLock { $0 += 1 }
    }

    override func stopLoading() {}
}

/// Coverage for `HackerRankClient` itself (#3, #32), driven through the in-process demo
/// server. Where `MockHackerRankServerTests` fetches and decodes fixtures directly, these
/// tests exercise the real client end-to-end: the endpoint paths it builds, the
/// `Page` envelope it returns, its following of an absolute `next` cursor across pages,
/// and `validateToken`'s behaviour. The mock's default `.success` scenario backs the
/// session, so the populated fixtures (including the multi-page tests collection) drive
/// the assertions.
@MainActor
struct HackerRankClientTests {
    /// A client for a mock account, so it routes to the bundled fixtures (via `isMock`,
    /// derived from the reserved demo token) and never hits the network — exercising the
    /// per-account demo routing rather than an injected session.
    private func makeClient(token: String = Account.demoToken) -> HackerRankClient {
        HackerRankClient(account: Account(label: "Demo", token: token))
    }

    // MARK: - Pagination

    @Test func `tests first page returns items and a next cursor`() async throws {
        let page = try await makeClient().testsPage()
        #expect(page.items.count == 3)
        #expect(page.items.first?.name == "Backend Engineer Screen")
        let next = try #require(page.next)
        #expect(next.contains("offset=3"))
    }

    @Test func `following the next cursor reaches the final page`() async throws {
        let client = makeClient()
        let first = try await client.testsPage()
        let cursor = try #require(first.next)

        // The cursor is an absolute URL; the client must request it verbatim rather than
        // rebuilding a first-page URL.
        let second = try await client.testsPage(after: cursor)
        #expect(second.items.count == 2)
        #expect(second.items.map(\.id) == ["t4", "t5"])
        #expect(second.next == nil)
    }

    @Test func `transient GET failures retry before succeeding`() async throws {
        TransientThenSuccessURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransientThenSuccessURLProtocol.self]
        let client = HackerRankClient(
            account: Account(label: "Org", token: "live-token"),
            session: URLSession(configuration: configuration)
        )

        let page = try await client.testsPage()

        #expect(page.items.map(\.id) == ["retried"])
        #expect(TransientThenSuccessURLProtocol.requestCount == 3)
    }

    @Test func `cancelling a GET does not retry it`() async throws {
        HangingURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingURLProtocol.self]
        let client = HackerRankClient(
            account: Account(label: "Org", token: "live-token"),
            session: URLSession(configuration: configuration)
        )
        let request = Task {
            try await client.testsPage()
        }

        while HangingURLProtocol.requestCount == 0 {
            await Task.yield()
        }
        request.cancel()

        do {
            _ = try await request.value
            Issue.record("expected cancellation")
        } catch let error as HackerRankError {
            guard case let .network(urlError) = error else {
                Issue.record("expected a network cancellation, got \(error)")
                return
            }

            #expect(urlError.code == .cancelled)
        } catch {
            Issue.record("expected HackerRankError, got \(error)")
        }
        #expect(HangingURLProtocol.requestCount == 1)
    }

    // MARK: - Other collections

    @Test func `questions page decodes through the client`() async throws {
        let page = try await makeClient().questionsPage()
        #expect(page.items.count == 3)
        #expect(page.next == nil)
    }

    @Test func `interviews page decodes through the client`() async throws {
        let page = try await makeClient().interviewsPage()
        #expect(page.items.count == 2)
        #expect(page.next == nil)
    }

    @Test func `users page decodes through the client`() async throws {
        let page = try await makeClient().usersPage()
        #expect(page.items.count == 4)
        #expect(page.items.contains { $0.companyAdmin == true })
        #expect(page.next == nil)
    }

    @Test func `teams page decodes through the client`() async throws {
        let page = try await makeClient().teamsPage()
        #expect(page.items.count == 3)
        #expect(page.items.contains { $0.developerCount == 12 })
        #expect(page.next == nil)
    }

    @Test func `team members page is routed under its team`() async throws {
        // The members path is "/teams/<id>/users"; the mock routes the "/users" segment to the
        // users fixture (#56).
        let page = try await makeClient().teamMembersPage(teamID: "tm1")
        #expect(page.items.count == 4)
        #expect(page.items.contains { $0.firstName == "Rhea" })
    }

    @Test func `candidates page is routed under its test`() async throws {
        // The candidates path also contains "/tests/", so the client must build
        // ".../tests/<id>/candidates" and the mock must route it to the candidates fixture.
        let page = try await makeClient().candidatesPage(testID: "t1")
        #expect(page.items.count == 5)
        #expect(page.items.contains { $0.fullName == "Ada Lovelace" })
    }

    @Test func `single candidate fixture remains distinct from its collection`() async throws {
        let candidate = try await makeClient().candidate(testID: "t1", candidateID: "c1")

        #expect(candidate.id == "c1")
        #expect(candidate.fullName == "Ada Lovelace")
        #expect(candidate.reportURL?.hasSuffix("/c1/report") == true)
        #expect(candidate.tags == ["shortlist", "single-read"])
    }

    @Test func `single user fixture carries richer account fields`() async throws {
        let user = try await makeClient().user(id: "u1")

        #expect(user.id == "u1")
        #expect(user.firstName == "Rhea")
        #expect(user.teams == ["tm1", "tm2"])
        #expect(user.companyAdmin == true)
        #expect(user.teamAdmin == true)
    }

    @Test func `single team fixture carries richer organisation fields`() async throws {
        let team = try await makeClient().team(id: "tm1")

        #expect(team.id == "tm1")
        #expect(team.name == "Backend Hiring")
        #expect(team.developerCount == 12)
        #expect(team.locations == ["London", "Berlin"])
        #expect(team.departments == ["Engineering", "Platform"])
    }

    @Test func `inviters fixture decodes as a paged resource`() async throws {
        let page = try await makeClient().testInviters(testID: "t1")

        #expect(page.items.map(\.id) == ["u1", "u2", "u-missing-email"])
        #expect(page.items.map(\.email) == ["rhea@example.com", "ian@example.com", ""])
        #expect(page.next == nil)
    }

    @Test func `interview template fixtures cover collection and detail routes`() async throws {
        let client = makeClient()
        let page = try await client.interviewTemplatesPage()
        let detail = try await client.interviewTemplate(id: 101)

        #expect(page.items.compactMap(\.id) == [101, 102])
        #expect(detail.id == 101)
        #expect(detail.name == "Backend Pairing")
        #expect(detail.status == 1)
        #expect(detail.editorAccess == true)
    }

    @Test func `invite template fixtures cover collection and detail routes`() async throws {
        let client = makeClient()
        let page = try await client.inviteTemplatesPage()
        let detail = try await client.inviteTemplate(id: "tpl-1")

        #expect(page.items.compactMap(\.id) == ["tpl-1", "tpl-2"])
        #expect(detail.id == "tpl-1")
        #expect(detail.subject == "Your HackerRank invite")
        #expect(detail.content?.isEmpty == false)
    }

    @Test func `SCIM fixtures cover user collection and detail routes`() async throws {
        let client = makeClient()
        let page = try await client.scimUsers()
        let detail = try await client.scimUser(id: "scim-u1")

        #expect(page.resources.compactMap(\.id) == ["scim-u1"])
        #expect(page.totalResults == 1)
        #expect(detail.userName == "rhea@example.com")
        #expect(detail.companyAdmin == true)
    }

    @Test func `SCIM fixtures cover group collection and detail routes`() async throws {
        let client = makeClient()
        let page = try await client.scimGroups()
        let detail = try await client.scimGroup(id: "scim-g1")

        #expect(page.resources.compactMap(\.id) == ["scim-g1"])
        #expect(page.totalResults == 1)
        #expect(detail.displayName == "Backend Hiring")
        #expect(detail.members?.count == 1)
    }

    @Test func `candidate write fixtures cover update cancel and report deletion`() async throws {
        let client = makeClient()
        let updated = try await client.updateCandidate(testID: "t1", candidateID: "c1")
        let cancelled = try await client.cancelCandidateInvite(testID: "t1", candidateID: "c1")
        let deleted = try await client.deleteCandidateReport(testID: "t1", candidateID: "c1")

        #expect(updated.id == "c-invited")
        #expect(cancelled.id == "c-invited")
        #expect(deleted.id == "c-invited")
    }

    @Test func `candidate report PDF fixture returns a sanitized URL`() async throws {
        let report = try await makeClient().candidateReportPDF(testID: "t1", candidateID: "c1")

        #expect(report.pdfURL == "https://www.hackerrank.com/x/candidates/c1/report.pdf")
    }

    @Test func `archive fixture completes without decoding an empty body`() async throws {
        try await makeClient().archiveTest(testID: "t1")
    }

    // MARK: - Token validation

    @Test func `validating an empty token fails before any request`() async {
        await #expect(throws: HackerRankError.self) {
            try await makeClient(token: "").validateToken()
        }
    }

    @Test func `validating a token against a 2xx response succeeds`() async throws {
        // The success scenario answers the validation probe with a populated tests page.
        try await makeClient().validateToken()
    }

    @Test func `demo failure scenarios are selected from the launch environment`() async throws {
        let account = Account.demo
        let key = DemoFailureScenario.environmentKey

        let empty = try await HackerRankClient(
            account: account,
            environment: [key: DemoFailureScenario.empty.rawValue]
        ).testsPage()
        #expect(empty.items.isEmpty)

        await #expect(throws: HackerRankError.self) {
            try await HackerRankClient(
                account: account,
                environment: [key: DemoFailureScenario.validation.rawValue]
            ).testsPage()
        }
        await #expect(throws: HackerRankError.self) {
            try await HackerRankClient(
                account: account,
                environment: [key: DemoFailureScenario.malformed.rawValue]
            ).testsPage()
        }
    }

    @Test func `every documented demo failure scenario has a deterministic response`() {
        #expect(DemoFailureScenario.allCases.map(\.rawValue) == [
            "empty", "validation", "throttled", "malformed", "server-error"
        ])
        #expect(DemoFailureScenario.throttled.response.status == 429)
        #expect(DemoFailureScenario.serverError.response.status == 503)
    }

    // MARK: - Current user (#72)

    @Test func `currentUser decodes the single users-me object`() async throws {
        // /users/me returns a single user object, not a paged envelope; it must decode straight
        // into User (the same shape as a People-list entry).
        let current = try await makeClient().currentUser()
        #expect(current.id == "u-me")
        #expect(current.email == "demo@example.com")
        #expect(current.firstName == "Demo")
        #expect(current.role == "admin")
    }

    @Test func `the bad-key demo account surfaces the server's 401`() async {
        // The mock 401s the bad-key token regardless of scenario, so this exercises the
        // client's unauthorized path end-to-end (not just the error mapping in isolation).
        let client = HackerRankClient(account: .badKeyDemo)
        await expectUnauthorized {
            _ = try await client.testsPage()
        }
    }
}
