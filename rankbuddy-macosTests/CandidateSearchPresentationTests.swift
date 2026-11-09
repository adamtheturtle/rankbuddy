//
//  CandidateSearchPresentationTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

@MainActor
struct CandidateSearchPresentationTests {
    @Test func `results lead with names and retain email as secondary information`() {
        let candidate = CandidateSearchPresentation(value: .object([
            "name": .string("  Ada Lovelace  "), "email": .string("ada@example.com"), "uuid": .string("candidate-1")
        ]))
        #expect(candidate.title == "Ada Lovelace")
        #expect(candidate.subtitle == "ada@example.com")
        #expect(candidate.identifier == "candidate-1")
        let fallback = CandidateSearchPresentation(value: .object([
            "name": .string(" \n"), "email": .string("ada@example.com")
        ]))
        #expect(fallback.title == "ada@example.com")
        #expect(fallback.subtitle == nil)
        #expect(CandidateSearchPresentation(value: .object([:])).title == "Unnamed candidate")
    }

    @Test func `profile and attempt dates accept API timezone offsets and fractional seconds`() throws {
        let rawStart = "2025-07-14T17:23:46+0000"
        let rawEnd = "2025-07-14T17:27:30.500Z"
        let candidate = CandidateSearchPresentation(value: .object([
            "created_at": .string(rawStart), "updated_at": .string(rawEnd)
        ]))
        let attempt = CandidateAttemptPresentation(value: .object([
            "test_id": .int(42), "attempt_id": .int(7),
            "attempt_starttime": .string(rawStart), "attempt_endtime": .string(rawEnd), "score": .double(92)
        ]), index: 0)
        for date in [candidate.date("created_at"), candidate.date("updated_at"), attempt.started, attempt.completed] {
            let formatted = try #require(date)
            #expect(formatted != rawStart)
            #expect(formatted != rawEnd)
            #expect(!formatted.contains("T17:"))
        }
        #expect(attempt.title == "Test 42")
        #expect(attempt.number("score") == "92")
        #expect(CandidateAttemptPresentation(value: .object([:]), index: 0).completed == nil)
        #expect(CandidateSearchPresentation(value: .object(["created_at": .string("unknown")]))
            .date("created_at") == "unknown")
    }

    @Test func `reports require web URLs and additional fields remain available`() {
        let attempt = CandidateAttemptPresentation(value: .object([
            "report_url": .string("https://www.hackerrank.com/report/7"), "extra_context": .string("Retain me")
        ]), index: 0)
        #expect(attempt.reportURL?.scheme == "https")
        #expect(attempt.additionalFields["extra_context"] == .string("Retain me"))
        #expect(CandidateAttemptPresentation(value: .object([
            "report_url": .string("file:///tmp/report")
        ]), index: 0).reportURL == nil)
    }

    @Test func `account search rows use candidate UUIDs rather than their page position`() async {
        let model = NativeBusinessCollection()
        await model.load(kind: .candidates, client: HackerRankClient(account: .demo), scimToken: nil,
                         query: [URLQueryItem(name: "query", value: "Ada")])
        #expect(model.error == nil)
        #expect(model.records.map(\.id) == ["cand-ada"])
        #expect(model.records.first.map { CandidateSearchPresentation(value: $0.value).title } == "Ada Lovelace")
    }
}
