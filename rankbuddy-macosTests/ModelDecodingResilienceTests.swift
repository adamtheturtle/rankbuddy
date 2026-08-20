//
//  ModelDecodingResilienceTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Drift-tolerant decoding coverage for the domain models (#4, #32). The read-only models
/// deliberately model only the fields the UI needs: every non-identifying field is optional,
/// snake_case keys are mapped, and unmodelled keys must be ignored so live API responses keep
/// decoding as HackerRank adds fields. These tests pin that contract for each model.
@MainActor
struct ModelDecodingResilienceTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Test

    @Test func `decodes with only the required id and name`() throws {
        let test = try decode(HackerRankKit.Test.self, #"{"id":"t1","name":"Screen"}"#)
        #expect(test.id == "t1")
        #expect(test.name == "Screen")
        #expect(test.startTime == nil)
        #expect(test.duration == nil)
        #expect(test.languages == nil)
        #expect(test.tags == nil)
    }

    @Test func `ignores unmodelled keys`() throws {
        let json = #"""
        {"id":"t1","name":"Screen","brand_new_field":42,"nested":{"a":1},"list":[1,2,3]}
        """#
        let test = try decode(HackerRankKit.Test.self, json)
        #expect(test.id == "t1")
        #expect(test.name == "Screen")
    }

    @Test func `maps snake_case keys and array fields`() throws {
        let json = #"""
        {"id":"t1","name":"Screen","unique_id":"uid","start_time":"2026-05-01T09:00:00Z",
         "end_time":"2026-06-01T09:00:00Z","cutoff_score":70,"enable_proctoring":true,
         "shuffle_questions":false,"languages":["python","go"],"questions":["q1","q2"]}
        """#
        let test = try decode(HackerRankKit.Test.self, json)
        #expect(test.uniqueID == "uid")
        #expect(test.startTime == "2026-05-01T09:00:00Z")
        #expect(test.cutoffScore == 70)
        #expect(test.enableProctoring == true)
        #expect(test.shuffleQuestions == false)
        #expect(test.languages == ["python", "go"])
        #expect(test.questions == ["q1", "q2"])
    }

    @Test func `fails when a required field is missing`() throws {
        #expect(throws: DecodingError.self) {
            try decode(HackerRankKit.Test.self, #"{"name":"No id"}"#)
        }
    }

    @Test func `decodes a section that omits its uuid`() throws {
        // Live tests include sections without a `uuid` (and sometimes without a `name`); one
        // such section must not fail the whole Test, which would break the entire Tests page.
        let json = #"""
        {"id":"t1","name":"Screen","sections":[
          {"name":"Coding","questions":2},
          {"uuid":"s2","name":"MCQ","questions":5},
          {}
        ]}
        """#
        let test = try decode(HackerRankKit.Test.self, json)
        let sections = try #require(test.sections)
        #expect(sections.count == 3)
        #expect(sections[0].uuid == nil)
        #expect(sections[0].displayName == "Coding")
        #expect(sections[0].id == "0-Coding")
        #expect(sections[1].id == "s2")
        // A wholly empty section still decodes with a generic label and a fallback id.
        #expect(sections[2].displayName == "Section")
        #expect(sections[2].id == "2")
    }

    @Test func `a uuid-less section does not break the surrounding page`() throws {
        // Reproduces the live failure: one test deep in a page had a section with no `uuid`,
        // which previously failed the whole `HackerRankPage<HackerRankKit.Test>` decode.
        let json = #"""
        {"data":[
          {"id":"t1","name":"First"},
          {"id":"t2","name":"Second","sections":[{"name":"Part 1","questions":3}]}
        ],"next":null}
        """#
        let page = try decode(HackerRankPage<HackerRankKit.Test>.self, json)
        #expect(page.pageItems.count == 2)
        #expect(page.pageItems[1].sections?.first?.displayName == "Part 1")
    }

    // MARK: - TestCandidate

    @Test func `candidate decodes with only id and email`() throws {
        let candidate = try decode(TestCandidate.self, #"{"id":"c5","email":"x@example.com"}"#)
        #expect(candidate.id == "c5")
        #expect(candidate.email == "x@example.com")
        #expect(candidate.fullName == nil)
        #expect(candidate.score == nil)
        #expect(candidate.plagiarismStatus == nil)
    }

    @Test func `candidate decodes an integer score as a Double`() throws {
        // The API sometimes emits whole scores without a decimal point.
        let candidate = try decode(TestCandidate.self, #"{"id":"c1","email":"a@b.com","score":80}"#)
        #expect(candidate.score == 80.0)
    }

    @Test func `candidate with no email is kept (defaulted), not dropped (#85)`() throws {
        // `email` is required in the schema but can be null/absent for an invited-but-unregistered
        // candidate. It must default rather than throw, or the page decoder drops the record.
        let candidate = try decode(TestCandidate.self, #"{"id":"c1"}"#)
        #expect(candidate.id == "c1")
        #expect(candidate.email.isEmpty)
        let nullEmail = try decode(TestCandidate.self, #"{"id":"c2","email":null}"#)
        #expect(nullEmail.email.isEmpty)
    }

    // MARK: - Question

    @Test func `question decodes with only the required fields`() throws {
        let question = try decode(Question.self, #"{"id":"q1","type":"mcq","name":"SQL"}"#)
        #expect(question.id == "q1")
        #expect(question.type == "mcq")
        #expect(question.maxScore == nil)
        #expect(question.languages == nil)
    }

    @Test func `question fails when type is missing`() throws {
        #expect(throws: DecodingError.self) {
            try decode(Question.self, #"{"id":"q1","name":"No type"}"#)
        }
    }

    // MARK: - Interview

    @Test func `interview decodes with only the required fields`() throws {
        let json = #"{"id":"i1","status":"scheduled","url":"https://hr.test/i1"}"#
        let interview = try decode(Interview.self, json)
        #expect(interview.id == "i1")
        #expect(interview.status == "scheduled")
        #expect(interview.url == "https://hr.test/i1")
        #expect(interview.thumbsUp == nil)
        #expect(interview.endedAt == nil)
    }

    @Test func `interview with no url or status is kept (defaulted), not dropped (#85)`() throws {
        // `status`/`url` are required in the schema but a freshly scheduled interview can lack a
        // url, and either can be null. They must default rather than throw, or the page decoder
        // drops the record — the root cause of "only old interviews" showing.
        let noURL = try decode(Interview.self, #"{"id":"i1","status":"ended"}"#)
        #expect(noURL.url.isEmpty)
        #expect(noURL.status == "ended")
        let nullBoth = try decode(Interview.self, #"{"id":"i2","status":null,"url":null}"#)
        #expect(nullBoth.id == "i2")
        #expect(nullBoth.status.isEmpty)
        #expect(nullBoth.url.isEmpty)
    }

    // MARK: - Team & User

    @Test func `team decodes counts and ignores extra keys`() throws {
        let json = #"""
        {"id":"team1","name":"Platform","recruiter_count":3,"developer_count":12,
         "locations":["London"],"departments":["Eng"],"unexpected":"ok"}
        """#
        let team = try decode(Team.self, json)
        #expect(team.id == "team1")
        #expect(team.recruiterCount == 3)
        #expect(team.developerCount == 12)
        #expect(team.locations == ["London"])
    }

    @Test func `user maps firstname and admin flags`() throws {
        let json = #"""
        {"id":"u1","email":"u@example.com","firstname":"Ada","lastname":"Lovelace",
         "company_admin":true,"team_admin":false,"activated":true,"teams":["team1"]}
        """#
        let user = try decode(User.self, json)
        #expect(user.firstName == "Ada")
        #expect(user.lastName == "Lovelace")
        #expect(user.companyAdmin == true)
        #expect(user.teamAdmin == false)
        #expect(user.teams == ["team1"])
    }

    @Test func `user with no email is kept (defaulted), not dropped (#85)`() throws {
        // `email` is required in the schema but SSO/pending/service accounts can lack one. It must
        // default rather than throw, or the page decoder drops the user — the root cause of "only
        // some users" showing.
        let user = try decode(User.self, #"{"id":"u1"}"#)
        #expect(user.id == "u1")
        #expect(user.email.isEmpty)
        let nullEmail = try decode(User.self, #"{"id":"u2","email":null}"#)
        #expect(nullEmail.email.isEmpty)
    }

    // MARK: - Page envelope

    @Test func `page decodes data and an absolute next url`() throws {
        let json = #"""
        {"data":[{"id":"t1","name":"One"},{"id":"t2","name":"Two"}],
         "next":"https://www.hackerrank.com/x/api/v3/tests?limit=2&offset=2","count":99}
        """#
        let page = try decode(HackerRankPage<HackerRankKit.Test>.self, json)
        #expect(page.pageItems.count == 2)
        #expect(page.nextPage == "https://www.hackerrank.com/x/api/v3/tests?limit=2&offset=2")
        // `total` is intentionally nil so the transport uses its next-walk, not page numbers.
        #expect(page.total == nil)
    }

    @Test func `page decodes a null next as the last page`() throws {
        let page = try decode(HackerRankPage<Question>.self, #"{"data":[],"next":null}"#)
        #expect(page.pageItems.isEmpty)
        #expect(page.nextPage == nil)
    }

    @Test func `a page drops a malformed item but keeps the good ones`() throws {
        // The middle test is missing its required `name`; leniency drops it so one bad record
        // on a live account doesn't fail the whole list (the page-level backstop for #5/#34).
        let json = #"""
        {"data":[
          {"id":"t1","name":"Good"},
          {"id":"t2"},
          {"id":"t3","name":"Also good"}
        ],"next":null}
        """#
        let page = try decode(HackerRankPage<HackerRankKit.Test>.self, json)
        #expect(page.pageItems.map(\.id) == ["t1", "t3"])
    }

    @Test func `a users page keeps records whose required email is null or absent (#85)`() throws {
        // The exact "only some users" bug: previously a user with a null/absent email threw and
        // the lenient page decode silently dropped it. Now all three must survive.
        let json = #"""
        {"data":[
          {"id":"u1","email":"a@example.com"},
          {"id":"u2","email":null},
          {"id":"u3"}
        ],"next":null}
        """#
        let page = try decode(HackerRankPage<User>.self, json)
        #expect(page.pageItems.map(\.id) == ["u1", "u2", "u3"])
    }

    @Test func `an interviews page keeps records with null status or absent url (#85)`() throws {
        // The "only old interviews" bug: a record missing url (or with null status) used to be
        // dropped. All three must survive now.
        let json = #"""
        {"data":[
          {"id":"i1","status":"completed","url":"https://hr.test/i1"},
          {"id":"i2","status":null,"url":"https://hr.test/i2"},
          {"id":"i3","status":"scheduled"}
        ],"next":null}
        """#
        let page = try decode(HackerRankPage<Interview>.self, json)
        #expect(page.pageItems.map(\.id) == ["i1", "i2", "i3"])
    }
}
