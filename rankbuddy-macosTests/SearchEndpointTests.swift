//
//  SearchEndpointTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the server-side search endpoints (#104): `GET /users/search` and
/// `GET /tests/{id}/candidates/search`. The demo `MockHackerRankURLProtocol` serves the
/// search routes and narrows its fixtures by the `search` term, so these tests confirm the
/// client builds the right request, decodes the paged envelope, and that the server's match is
/// what comes back (not the whole list).
@MainActor
struct SearchEndpointTests {
    private var client: HackerRankClient {
        HackerRankClient(account: Account(label: "Demo", token: Account.demoToken))
    }

    // MARK: - Candidate search

    @Test func `candidate search returns only the matching candidate`() async throws {
        let page = try await client.searchCandidates(testID: "t1", query: "ada")
        #expect(page.items.count == 1)
        #expect(page.items.first?.fullName == "Ada Lovelace")
    }

    @Test func `candidate search matches on email too`() async throws {
        let page = try await client.searchCandidates(testID: "t1", query: "grace@example.com")
        #expect(page.items.map(\.fullName) == ["Grace Hopper"])
    }

    @Test func `candidate search with no match is empty, not the whole list`() async throws {
        let page = try await client.searchCandidates(testID: "t1", query: "no-such-person")
        #expect(page.items.isEmpty)
    }

    // MARK: - User search

    @Test func `user search returns only the matching user`() async throws {
        let page = try await client.searchUsers(query: "rhea")
        #expect(page.items.count == 1)
        #expect(page.items.first?.email == "rhea@example.com")
    }

    @Test func `user search is case-insensitive and matches a name`() async throws {
        let page = try await client.searchUsers(query: "INTERVIEWER")
        #expect(page.items.map(\.email) == ["ian@example.com"])
    }

    // MARK: - Routing

    @Test func `a search path is not swallowed by the list route`() async throws {
        // `/users/search` contains `/users`; the mock must route it to the (filtered) search
        // body, not the full users list.
        let page = try await client.searchUsers(query: "pat")
        #expect(page.items.count == 1)
        #expect(page.items.first?.firstName == "Pat")
    }
}
