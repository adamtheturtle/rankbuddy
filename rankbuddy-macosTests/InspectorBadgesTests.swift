//
//  InspectorBadgesTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the inspector-header status chips (#54): the per-model `inspectorBadges`
/// extensions that drive the detail panes' header. The chip rendering is verified visually
/// via the detail previews; these lock in the pure badge-derivation logic.
@MainActor
struct InspectorBadgesTests {
    @Test func `a team's chips report its developer and recruiter counts`() throws {
        let json = #"{"id":"tm1","name":"Backend Hiring","developer_count":12,"recruiter_count":3}"#
        let team = try JSONDecoder().decode(Team.self, from: Data(json.utf8))
        #expect(team.inspectorBadges.map(\.text) == ["12 developers", "3 recruiters"])
    }

    @Test func `a team with no recruiters omits the recruiter chip and pluralises one developer`() throws {
        let json = #"{"id":"tm2","name":"Solo","developer_count":1,"recruiter_count":0}"#
        let team = try JSONDecoder().decode(Team.self, from: Data(json.utf8))
        #expect(team.inspectorBadges.map(\.text) == ["1 developer"])
    }

    @Test func `a user's chips report role, status, and admin scope`() throws {
        let json = #"""
        {"id":"u1","email":"rhea@example.com","role":"recruiter","status":"active",
         "company_admin":true,"team_admin":true}
        """#
        let user = try JSONDecoder().decode(User.self, from: Data(json.utf8))
        // Company admin wins over team admin when both are set.
        #expect(user.inspectorBadges.map(\.text) == ["Recruiter", "Active", "Company admin"])
    }

    @Test func `inactive users and archived questions do not receive active status icons`() throws {
        let userJSON = #"{"id":"u2","email":"inactive@example.com","status":"deactivated"}"#
        let questionJSON = #"{"id":"q1","name":"Old question","type":"coding","status":"archived"}"#
        let user = try JSONDecoder().decode(User.self, from: Data(userJSON.utf8))
        let question = try JSONDecoder().decode(Question.self, from: Data(questionJSON.utf8))

        #expect(user.inspectorBadges.last?.systemImage == "xmark.circle.fill")
        #expect(question.inspectorBadges.last?.systemImage == "archivebox.fill")
    }

    @Test func `unknown question and user statuses use neutral status icons`() throws {
        let userJSON = #"{"id":"u3","email":"unknown@example.com","status":"mystery"}"#
        let questionJSON = #"{"id":"q2","name":"Mystery","type":"coding","status":"mystery"}"#
        let user = try JSONDecoder().decode(User.self, from: Data(userJSON.utf8))
        let question = try JSONDecoder().decode(Question.self, from: Data(questionJSON.utf8))

        #expect(user.inspectorBadges.last?.systemImage == "circle.fill")
        #expect(question.inspectorBadges.last?.systemImage == "circle.fill")
    }

    @Test func `an interview's single chip capitalises its status`() throws {
        let json = #"{"id":"i1","status":"completed","url":"https://example.com/i1"}"#
        let interview = try JSONDecoder().decode(Interview.self, from: Data(json.utf8))
        #expect(interview.inspectorBadges.map(\.text) == ["Completed"])
    }

    @Test func `a flagged candidate surfaces a plagiarism chip alongside its status chips`() throws {
        let json = #"""
        {"id":"c3","email":"grace@example.com","full_name":"Grace Hopper",
         "status":7,"ats_state":22,"plagiarism_status":true}
        """#
        let candidate = try JSONDecoder().decode(TestCandidate.self, from: Data(json.utf8))
        #expect(candidate.inspectorBadges.contains { $0.text == "Plagiarism" })
    }
}
