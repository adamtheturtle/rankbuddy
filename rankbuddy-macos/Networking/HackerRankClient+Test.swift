//
//  HackerRankClient+Test.swift
//  rankbuddy-macos
//

import Foundation
import PaginatedRESTClient

extension HackerRankClient {
    /// The richer single-test read (`GET /tests/{id}`) backing the detail pane (#105). Adds the
    /// candidate login links, the master password, and the MCQ scoring over the list row.
    func test(id: String) async throws -> TestDetail {
        let url = baseURL.appending(path: "\(Self.apiV3)/tests/\(Self.pathSegment(id))")
        return try await rest.performWithRetry(TestDetail.self, request: rest.authorizedGET(url))
    }
}
