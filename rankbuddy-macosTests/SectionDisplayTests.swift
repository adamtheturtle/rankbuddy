//
//  SectionDisplayTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the People/Teams section display helpers (#36): `User.displayName` and
/// `Team.memberSummary`, the pure derivations that drive the new rows.
@MainActor
struct SectionDisplayTests {
    private func decode<T: Decodable>(_: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - User.displayName

    @Test func `display name joins first and last name`() throws {
        let user = try decode(User.self, #"{"id":"u1","email":"r@x.com","firstname":"Rhea","lastname":"Recruiter"}"#)
        #expect(user.displayName == "Rhea Recruiter")
    }

    @Test func `display name uses whichever name part is present`() throws {
        let user = try decode(User.self, #"{"id":"u1","email":"r@x.com","firstname":"Rhea"}"#)
        #expect(user.displayName == "Rhea")
    }

    @Test func `display name falls back to the email when unnamed`() throws {
        let user = try decode(User.self, #"{"id":"u1","email":"r@x.com"}"#)
        #expect(user.displayName == "r@x.com")
    }

    @Test func `display name trims parts and falls back when they contain only whitespace`() throws {
        let named = try decode(
            User.self,
            #"{"id":"u1","email":"r@x.com","firstname":" Rhea ","lastname":"\nRecruiter\t"}"#
        )
        let unnamed = try decode(
            User.self,
            #"{"id":"u2","email":"blank@x.com","firstname":" ","lastname":"\n\t"}"#
        )

        #expect(named.displayName == "Rhea Recruiter")
        #expect(unnamed.displayName == "blank@x.com")
    }

    // MARK: - Team.memberSummary

    @Test func `member summary lists both counts`() throws {
        let team = try decode(Team.self, #"{"id":"t1","name":"Backend","recruiter_count":3,"developer_count":12}"#)
        #expect(team.memberSummary == "3 recruiters · 12 developers")
    }

    @Test func `member summary singularises a count of one`() throws {
        let team = try decode(Team.self, #"{"id":"t1","name":"Backend","recruiter_count":1,"developer_count":1}"#)
        #expect(team.memberSummary == "1 recruiter · 1 developer")
    }

    @Test func `member summary includes interviewers when present`() throws {
        let team = try decode(Team.self, #"""
        {"id":"t1","name":"Backend","recruiter_count":3,"developer_count":12,"interviewer_count":8}
        """#)
        #expect(team.memberSummary == "3 recruiters · 12 developers · 8 interviewers")
        #expect(team.transferFields.map(\.0) == [
            "Name", "Members", "Recruiters", "Developers", "Interviewers"
        ])
        #expect(team.transferFields.last?.1 == "8")
    }

    @Test func `member summary omits an absent count`() throws {
        let team = try decode(Team.self, #"{"id":"t1","name":"Backend","developer_count":5}"#)
        #expect(team.memberSummary == "5 developers")
    }

    @Test func `member summary is nil when no counts are known`() throws {
        let team = try decode(Team.self, #"{"id":"t1","name":"Backend"}"#)
        #expect(team.memberSummary == nil)
    }
}
