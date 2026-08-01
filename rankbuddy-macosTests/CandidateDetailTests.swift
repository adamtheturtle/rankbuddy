//
//  CandidateDetailTests.swift
//  rankbuddy-macosTests
//

import HackerRankKit
@testable import rankbuddy_macos
import Testing

struct CandidateDetailTests {
    @Test func `candidate update overlays preserve rich detail`() {
        let candidate = TestCandidate(
            id: "c1",
            email: "ada@example.com",
            fullName: "Ada",
            score: 98,
            status: 2,
            tags: ["old"],
            feedback: "Strong",
            reportURL: "https://example.com/report",
            plagiarismStatus: false,
            outOfWindowEvents: 1
        )

        let updated = candidate.applying(CandidateUpdateOptions(fullName: "Ada Lovelace", tags: []))

        #expect(updated.fullName == "Ada Lovelace")
        #expect(updated.tags?.isEmpty == true)
        #expect(updated.email == candidate.email)
        #expect(updated.score == candidate.score)
        #expect(updated.status == candidate.status)
        #expect(updated.feedback == candidate.feedback)
        #expect(updated.reportURL == candidate.reportURL)
        #expect(updated.plagiarismStatus == candidate.plagiarismStatus)
        #expect(updated.outOfWindowEvents == candidate.outOfWindowEvents)
    }
}
