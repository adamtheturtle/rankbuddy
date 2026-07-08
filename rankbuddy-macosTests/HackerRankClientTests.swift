//
//  HackerRankClientTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
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
        do {
            _ = try await client.testsPage()
            Issue.record("expected an unauthorized error")
        } catch let error as HackerRankError {
            guard case let .http(status, _) = error else {
                Issue.record("expected .http, got \(error)")
                return
            }

            #expect(status == 401)
        } catch {
            Issue.record("expected HackerRankError, got \(error)")
        }
    }
}
