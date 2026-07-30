//
//  SpotlightKeywordSourceTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

@MainActor
struct SpotlightKeywordSourceTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func `a question brief excludes private problem text`() throws {
        let question = try decode(Question.self, #"""
        {"id":"q1","type":"code","name":"Two Sum","tags":["arrays","hashing"],
         "skills":["Problem Solving"],"languages":["python","cpp"],
         "problem_statement":"Given an array, return indices of the two numbers that add up to a target."}
        """#)

        let source = try #require(SpotlightKeywordSource.text(for: question))
        #expect(source.contains("Title: Two Sum"))
        #expect(source.contains("Tags: arrays, hashing"))
        #expect(source.contains("Skills: Problem Solving"))
        #expect(source.contains("Languages: python, cpp"))
        #expect(!source.contains("add up to a target"))
    }

    @Test func `a question with only a title yields no brief`() throws {
        let question = try decode(Question.self, #"""
        {"id":"q2","type":"code","name":"Mystery"}
        """#)

        #expect(SpotlightKeywordSource.text(for: question) == nil)
    }

    @Test func `a brief contains only normalized visible metadata text`() throws {
        let question = try decode(Question.self, #"""
        {"id":"q3","type":"code","name":"<b>Two&nbsp; Sum</b>",
         "tags":["<i>arrays</i>","<script>ignore me</script>"],
         "skills":["Problem\n   Solving"]}
        """#)

        let source = try #require(SpotlightKeywordSource.text(for: question))
        #expect(source.contains("Title: Two Sum"))
        #expect(source.contains("Tags: arrays"))
        #expect(source.contains("Skills: Problem Solving"))
        #expect(!source.contains("<"))
        #expect(!source.contains("ignore me"))
    }

    @Test func `a test brief excludes private instructions`() throws {
        let test = try decode(HackerRankKit.Test.self, #"""
        {"id":"t1","name":"Backend Screen","tags":["sql","api"],"languages":["go"],
         "instructions":"Complete   all\n\nquestions   within the time limit."}
        """#)

        let source = try #require(SpotlightKeywordSource.text(for: test))
        #expect(source.contains("Name: Backend Screen"))
        #expect(source.contains("Tags: sql, api"))
        #expect(source.contains("Languages: go"))
        #expect(!source.contains("Complete all questions"))
    }

    @Test func `a test with only a name yields no brief`() throws {
        let test = try decode(HackerRankKit.Test.self, #"""
        {"id":"t2","name":"Untitled"}
        """#)

        #expect(SpotlightKeywordSource.text(for: test) == nil)
    }

    @Test func `interview notes never produce a keyword brief`() throws {
        let withNotes = try decode(Interview.self, #"""
        {"id":"i1","status":"active","url":"https://x","title":"Systems Round",
         "notes":"Assess distributed systems and caching."}
        """#)
        #expect(SpotlightKeywordSource.text(for: withNotes) == nil)

        let titleOnly = try decode(Interview.self, #"""
        {"id":"i2","status":"active","url":"https://x","title":"Quick Chat"}
        """#)
        #expect(SpotlightKeywordSource.text(for: titleOnly) == nil)
    }
}
