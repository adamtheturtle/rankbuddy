//
//  TeamDetailTests.swift
//  rankbuddy-macosTests
//

import HackerRankKit
@testable import rankbuddy_macos
import Testing

struct TeamDetailTests {
    @Test func `team update overlays preserve rich detail`() {
        let team = Team(
            id: "team-1",
            name: "Platform",
            owner: "user-1",
            createdAt: "2026-01-01T00:00:00Z",
            recruiterCount: 3,
            developerCount: 4,
            interviewerCount: 5,
            locations: ["London"],
            departments: ["Engineering"]
        )

        let updated = team.applying(TeamUpdateOptions(name: "Infrastructure", locations: []))

        #expect(updated.name == "Infrastructure")
        #expect(updated.locations?.isEmpty == true)
        #expect(updated.departments == team.departments)
        #expect(updated.owner == team.owner)
        #expect(updated.createdAt == team.createdAt)
        #expect(updated.recruiterCount == team.recruiterCount)
        #expect(updated.developerCount == team.developerCount)
        #expect(updated.interviewerCount == team.interviewerCount)
    }
}
