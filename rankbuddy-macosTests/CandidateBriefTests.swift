//
//  CandidateBriefTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

@MainActor
struct CandidateBriefTests {
    private func candidate(_ json: String) throws -> TestCandidate {
        try JSONDecoder().decode(TestCandidate.self, from: Data(json.utf8))
    }

    @Test func `facts cover score, status, integrity, plagiarism, and proctoring`() throws {
        let candidate = try candidate(#"""
        {"id":"c3","email":"grace@example.com","full_name":"Grace Hopper","score":58.0,
         "percentage_score":58.0,"integrity_status":"review","plagiarism_status":true,
         "status":7,"ats_state":22,"out_of_window_events":4,"out_of_window_duration":95.0,
         "editor_paste_count":7}
        """#)

        let facts = CandidateBrief.facts(for: candidate)
        #expect(facts.contains("Score: 58 (58%)"))
        #expect(facts.contains("Attempt status: Reports ready"))
        #expect(facts.contains("Pipeline status: Rejected"))
        #expect(facts.contains("Integrity check: review"))
        #expect(facts.contains("Plagiarism: flagged"))
        #expect(facts.contains("Left the test window 4 times"))
        #expect(facts.contains("Editor pastes: 7"))
    }

    @Test func `the brief never includes the candidate's name or email`() throws {
        let candidate = try candidate(#"""
        {"id":"c1","email":"ada@example.com","full_name":"Ada Lovelace","score":92.0,"status":7}
        """#)

        let joined = CandidateBrief.facts(for: candidate).joined(separator: "\n")
        #expect(!joined.contains("ada@example.com"))
        #expect(!joined.contains("Ada Lovelace"))
    }

    @Test func `a single out-of-window event is not pluralised`() throws {
        let candidate = try candidate(#"""
        {"id":"c1","email":"a@example.com","score":80.0,"status":7,"out_of_window_events":1}
        """#)
        #expect(CandidateBrief.facts(for: candidate).contains("Left the test window 1 time"))
    }

    @Test func `a bare invited candidate has no facts and no prompt`() throws {
        let candidate = try candidate(#"""
        {"id":"c4","email":"noname@example.com"}
        """#)
        #expect(CandidateBrief.facts(for: candidate).isEmpty)
        #expect(CandidateBrief.prompt(for: candidate) == nil)
    }

    @Test func `the prompt lists the signals as bullets`() throws {
        let candidate = try candidate(#"""
        {"id":"c1","email":"a@example.com","score":92.0,"status":7}
        """#)
        let prompt = try #require(CandidateBrief.prompt(for: candidate))
        #expect(prompt.contains("- Score: 92"))
        #expect(prompt.contains("- Attempt status: Reports ready"))
    }
}
