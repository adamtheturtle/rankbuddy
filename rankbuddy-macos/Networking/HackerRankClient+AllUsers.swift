//
//  HackerRankClient+AllUsers.swift
//  rankbuddy-macos
//

import Foundation
import PaginatedRESTClient

extension HackerRankClient {
    /// Loads the organisation's users as one list by fetching every page **in parallel** by offset
    /// (#86). People is bounded — an org has thousands of members, not the 87k of interviews — and
    /// the API exposes no name-search parameter, so loading the whole list is what lets People
    /// search match any user by name or email instead of only the first page. The first page gives
    /// the `total`; the rest are fetched concurrently (bounded, to stay gentle on the rate limiter)
    /// and reassembled in offset order. Bounded by `maxUsers` so a pathologically huge org can't
    /// drain unbounded; if `total` is absent it returns just the first page.
    func allUsers(maxUsers: Int = 6000) async throws -> [User] {
        let path = "\(Self.apiV3)/users"
        let first = try await offsetUsersPage(path: path, offset: 0)
        var all = first.data
        let total = min(first.totalCount ?? all.count, maxUsers)
        guard !all.isEmpty, all.count < total else { return all }

        let offsets = Array(stride(from: all.count, to: total, by: Self.pageSize))
        var byOffset: [Int: [User]] = [:]
        var pending = offsets[...]
        try await withThrowingTaskGroup(of: (Int, [User]).self) { group in
            func enqueueNext() {
                guard let offset = pending.first else { return }

                pending = pending.dropFirst()
                group.addTask { [self] in try await (offset, offsetUsersPage(path: path, offset: offset).data) }
            }
            for _ in 0 ..< 5 {
                enqueueNext()
            } // up to 5 pages in flight at once
            while let (offset, users) = try await group.next() {
                byOffset[offset] = users
                enqueueNext()
            }
        }
        for offset in offsets {
            all += byOffset[offset] ?? []
        }
        return all
    }

    /// Fetches one users page at an explicit `offset` (for the parallel `allUsers` fan-out).
    private func offsetUsersPage(path: String, offset: Int) async throws -> HackerRankPage<User> {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(Self.pageSize)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        guard let url = components?.url else {
            throw HackerRankError.http(status: 0, body: "Could not build the users page URL.")
        }

        return try await rest.performWithRetry(HackerRankPage<User>.self, request: rest.authorizedGET(url))
    }
}
