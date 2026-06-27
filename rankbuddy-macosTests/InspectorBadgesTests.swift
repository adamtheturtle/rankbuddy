//
//  InspectorBadgesTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the inspector-header status chips (#54): the per-model `inspectorBadges`
/// extensions that drive the detail panes' header. The chip rendering is verified visually
/// via the detail previews; these lock in the pure badge-derivation logic.
@MainActor
struct InspectorBadgesTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func `a team's chips report its developer and recruiter counts`() throws {
        let team = try decode(Team.self, #"""
        {"id":"tm1","name":"Backend Hiring","developer_count":12,"recruiter_count":3}
        """#)
        #expect(team.inspectorBadges.map(\.text) == ["12 developers", "3 recruiters"])
    }

    @Test func `a team with no recruiters omits the recruiter chip and pluralises one developer`() throws {
        let team = try decode(Team.self, #"{"id":"tm2","name":"Solo","developer_count":1,"recruiter_count":0}"#)
        #expect(team.inspectorBadges.map(\.text) == ["1 developer"])
    }

    @Test func `a user's chips report role, status, and admin scope`() throws {
        let user = try decode(User.self, #"""
        {"id":"u1","email":"rhea@example.com","role":"recruiter","status":"active",
         "company_admin":true,"team_admin":true}
        """#)
        // Company admin wins over team admin when both are set.
        #expect(user.inspectorBadges.map(\.text) == ["Recruiter", "Active", "Company admin"])
    }

    @Test func `an interview's single chip capitalises its status`() throws {
        let interview = try decode(Interview.self, #"{"id":"i1","status":"completed","url":"https://example.com/i1"}"#)
        #expect(interview.inspectorBadges.map(\.text) == ["Completed"])
    }

    @Test func `a flagged candidate surfaces a plagiarism chip alongside its status chips`() throws {
        let candidate = try decode(TestCandidate.self, #"""
        {"id":"c3","email":"grace@example.com","full_name":"Grace Hopper",
         "status":7,"ats_state":22,"plagiarism_status":true}
        """#)
        #expect(candidate.inspectorBadges.contains { $0.text == "Plagiarism" })
    }
}
