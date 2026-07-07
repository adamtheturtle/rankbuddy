//
//  HackerRankClient+Search.swift
//  rankbuddy-macos
//

import Foundation
import PaginatedRESTClient

extension HackerRankClient {
    /// Searches the organisation's users **server-side** (`GET /users/search?search=`) (#104).
    ///
    /// The v3 API does expose a free-text user search after all — earlier notes (#86) wrongly
    /// concluded it didn't — so a large org (thousands of members) can be searched by the server
    /// rather than by loading the whole list and filtering loaded rows. Returns a paged envelope
    /// in the same shape as the `/users` list, so the cursor-following pattern is identical.
    func searchUsers(query: String, after cursor: String? = nil) async throws -> Page<User> {
        try await searchPage(
            HackerRankPage<User>.self,
            path: "\(Self.apiV3)/users/search",
            query: query,
            cursor: cursor
        )
    }

    /// Searches a test's candidates **server-side** (`GET /tests/{id}/candidates/search?search=`)
    /// (#104). There was no candidate search before — the list filtered only loaded rows — so for a
    /// test with many candidates a match deep in the list was unreachable. Returns the same paged
    /// shape as the `/candidates` list.
    func searchCandidates(testID: String, query: String, after cursor: String? = nil) async throws
        -> Page<TestCandidate> {
        try await searchPage(
            HackerRankPage<TestCandidate>.self,
            path: "\(Self.apiV3)/tests/\(Self.pathSegment(testID))/candidates/search",
            query: query,
            cursor: cursor
        )
    }

    /// Fetches one page of a server-side search: the first page (base + path + `search` + `limit`)
    /// when `cursor` is `nil`, or the absolute `next` cursor URL otherwise (which already carries
    /// the search term). Mirrors `HackerRankClient.page`, kept here because that funnel is private
    /// to its file, per the repo's split-file rule.
    private func searchPage<Item: Decodable & Sendable>(
        _: HackerRankPage<Item>.Type,
        path: String,
        query: String,
        cursor: String?
    ) async throws -> Page<Item> {
        let url = try searchURL(path: path, query: query, cursor: cursor)
        let response = try await rest.performWithRetry(HackerRankPage<Item>.self, request: rest.authorizedGET(url))
        return Page(items: response.data, next: response.next, totalCount: response.totalCount)
    }

    private func searchURL(path: String, query: String, cursor: String?) throws -> URL {
        if let cursor {
            guard let url = URL(string: cursor) else {
                throw HackerRankError.http(status: 0, body: "Invalid next-page URL.")
            }

            return url
        }

        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: String(Self.pageSize))
        ]
        guard let url = components?.url else {
            throw HackerRankError.http(status: 0, body: "Could not build the search URL.")
        }

        return url
    }
}
