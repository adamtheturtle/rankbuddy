//
//  HackerRankClient+Interview.swift
//  rankbuddy-macos
//

import Foundation
import PaginatedRESTClient

extension HackerRankClient {
    /// The richer single-interview read (`GET /interviews/{id}`) backing the detail pane (#103).
    /// Adds the scheduled window, interviewers, owner, candidate, and result/résumé links over
    /// the fields the list row carries.
    func interview(id: String) async throws -> InterviewDetail {
        let url = baseURL.appending(path: "\(Self.apiV3)/interviews/\(Self.pathSegment(id))")
        return try await rest.performWithRetry(InterviewDetail.self, request: rest.authorizedGET(url))
    }

    /// The interview's conversation transcript (`GET /interviews/{id}/transcript`) — the
    /// spoken/typed messages only; the collaborative pad's source code is not exposed (#103).
    func interviewTranscript(id: String) async throws -> InterviewTranscript {
        let url = baseURL.appending(path: "\(Self.apiV3)/interviews/\(Self.pathSegment(id))/transcript")
        return try await rest.performWithRetry(InterviewTranscript.self, request: rest.authorizedGET(url))
    }
}
