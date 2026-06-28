//
//  HackerRankClient+Question.swift
//  rankbuddy-macos
//

import Foundation
import PaginatedRESTClient

extension HackerRankClient {
    /// The richer single-question read (`GET /questions/{id}`) backing the detail pane (#105).
    /// Adds the MCQ options/answer and internal notes over the fields the list row carries.
    func question(id: String) async throws -> QuestionDetail {
        let url = baseURL.appending(path: "\(Self.apiV3)/questions/\(Self.pathSegment(id))")
        return try await rest.performWithRetry(QuestionDetail.self, request: rest.authorizedGET(url))
    }
}
