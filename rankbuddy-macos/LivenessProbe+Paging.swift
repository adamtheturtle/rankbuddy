//
//  LivenessProbe+Paging.swift
//  rankbuddy-macos
//

import HackerRankKit

extension LivenessProbe {
    /// Bounds background work while covering substantially more than the API's first page.
    static let pageLimit = 20

    nonisolated static func pagedInterviews(
        limit: Int,
        page: @Sendable (String?) async throws -> Page<Interview>
    ) async throws -> [Interview] {
        guard limit > 0 else { return [] }

        var interviews: [Interview] = []
        var cursor: String?
        var seenCursors: Set<String> = []
        for _ in 0 ..< limit {
            let result = try await page(cursor)
            interviews.append(contentsOf: result.items)
            guard let next = result.next, seenCursors.insert(next).inserted else { break }

            cursor = next
        }
        return interviews
    }
}
