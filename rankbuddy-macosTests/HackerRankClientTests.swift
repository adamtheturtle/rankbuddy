import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for `HackerRankClient` itself (#3, #32), driven through the in-process demo
/// server. Where `MockHackerRankServerTests` fetches and decodes fixtures directly, these
/// tests exercise the real client end-to-end: the endpoint paths it builds, the
/// `Page` envelope it returns, its following of an absolute `next` cursor across pages,
/// and `validateToken`'s behaviour. The mock's default `.success` scenario backs the
/// session, so the populated fixtures (including the multi-page tests collection) drive
/// the assertions.
@MainActor
struct HackerRankClientTests {
    /// A client for a mock account, so it routes to the bundled fixtures (via `isMock`) and
    /// never hits the network — exercising the per-account demo routing rather than an
    /// injected session.
    private func makeClient(token: String = "demo-token") -> HackerRankClient {
        HackerRankClient(account: Account(label: "Demo", token: token, isMock: true))
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

    @Test func `candidates page is routed under its test`() async throws {
        // The candidates path also contains "/tests/", so the client must build
        // ".../tests/<id>/candidates" and the mock must route it to the candidates fixture.
        let page = try await makeClient().candidatesPage(testID: "t1")
        #expect(page.items.count == 5)
        #expect(page.items.contains { $0.fullName == "Ada Lovelace" })
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
}
