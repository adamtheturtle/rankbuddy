//
//  AllUsersLoaderTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// A throwaway in-test server that paginates a synthetic users collection by `offset`/`limit`
/// and reports a `total`, so `HackerRankClient.allUsers` can be exercised end-to-end: the
/// first page yields the total and the rest are fanned out in parallel by offset (#86).
private final class PaginatedUsersURLProtocol: URLProtocol {
    static let total = 250

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              )
        else { return }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let offset = items.first { $0.name == "offset" }.flatMap { Int($0.value ?? "") } ?? 0
        let limit = items.first { $0.name == "limit" }.flatMap { Int($0.value ?? "") } ?? 100
        let end = min(offset + limit, Self.total)
        let records = (offset ..< max(offset, end)).map { index in
            "{\"id\":\"u\(index)\",\"email\":\"user\(index)@example.com\"," +
                "\"firstname\":\"First\(index)\",\"lastname\":\"Last\(index)\"}"
        }.joined(separator: ",")
        let body = "{\"data\":[\(records)],\"total\":\(Self.total)}"

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
struct AllUsersLoaderTests {
    private func client() -> HackerRankClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PaginatedUsersURLProtocol.self]
        let session = URLSession(configuration: configuration)
        // A non-demo token, with an explicit session so the parallel fan-out hits the in-test server.
        return HackerRankClient(account: Account(label: "Org", token: "live-token-xyz"), session: session)
    }

    @Test func `allUsers loads every page and keeps them in order`() async throws {
        let users = try await client().allUsers()
        // All 250 across the paged collection, none dropped or duplicated, reassembled in offset order.
        #expect(users.count == PaginatedUsersURLProtocol.total)
        #expect(users.map(\.id) == (0 ..< PaginatedUsersURLProtocol.total).map { "u\($0)" })
        // A record deep past the first page is present — the whole point: search can now match it.
        #expect(users.contains { $0.id == "u200" })
    }

    @Test func `allUsers respects the maxUsers bound`() async throws {
        let users = try await client().allUsers(maxUsers: 120)
        // Page size is 100, so the bound is satisfied at a page boundary (first page + nothing past 120).
        #expect(users.count <= 120 + 100)
        #expect(users.count >= 120)
        #expect(users.first?.id == "u0")
    }
}
