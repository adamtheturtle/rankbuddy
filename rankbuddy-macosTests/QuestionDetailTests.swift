//
//  QuestionDetailTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the richer single-question read (#105): `QuestionDetail`'s resilient decoding and
/// the client method that fetches it through the demo server.
@MainActor
struct QuestionDetailTests {
    private func makeClient() -> HackerRankClient {
        HackerRankClient(account: Account(label: "Demo", token: Account.demoToken))
    }

    @Test func `question detail decodes through the client`() async throws {
        let detail = try await makeClient().question(id: "q3")
        #expect(detail.options == ["INNER JOIN", "LEFT JOIN", "RIGHT JOIN", "FULL OUTER JOIN"])
        #expect(detail.answer == .option(2))
        #expect(detail.internalNotes?.isEmpty == false)
        #expect(detail.hasContent)
    }

    @Test func `detail tolerates a coding question with no options or answer`() throws {
        // A coding question carries no MCQ fields; the detail must still decode.
        let json = #"{"id":"q1","type":"code","name":"Two Sum"}"#
        let detail = try JSONDecoder().decode(QuestionDetail.self, from: Data(json.utf8))
        #expect(detail.options.isEmpty)
        #expect(detail.answer == nil)
        #expect(detail.internalNotes == nil)
        #expect(detail.hasContent == false)
    }

    @Test func `the single-question route is distinct from the list route`() async throws {
        // The list returns three questions; the single read returns just the detailed one,
        // proving the mock routes "/questions/{id}" separately from "/questions".
        let list = try await makeClient().questionsPage()
        #expect(list.items.count == 3)
        let detail = try await makeClient().question(id: "q3")
        #expect(!detail.options.isEmpty)
    }

    @Test func `empty list updates clear question metadata`() throws {
        let json = #"""
        {"id":"q1","type":"code","name":"Two Sum","languages":["swift"],
         "skills":["Algorithms"],"tags":["arrays"]}
        """#
        let question = try JSONDecoder().decode(Question.self, from: Data(json.utf8))
        let updated = question.applying(
            QuestionMetadataChanges(languages: [], tags: [])
        )

        #expect(updated.languages?.isEmpty == true)
        #expect(updated.tags?.isEmpty == true)
    }

    @Test func `explicit zero duration survives the edit overlay`() {
        let question = Question(id: "q1", type: "code", name: "Two Sum", recommendedDuration: 30, maxScore: 100)
        var overlay = QuestionEditOverlay()
        overlay.merge(QuestionMetadataChanges(recommendedDuration: 0))
        #expect(overlay.applying(to: question).recommendedDuration == 0)
        overlay.merge(QuestionMetadataChanges(name: "Renamed"))
        #expect(overlay.applying(to: question).recommendedDuration == 0)
        #expect(overlay.applying(to: question).maxScore == 100)
    }

    @Test func `edit overlay preserves newer unedited metadata`() throws {
        let original = try JSONDecoder().decode(
            Question.self,
            from: Data(#"{"id":"q1","type":"code","name":"Old","languages":["swift"]}"#.utf8)
        )
        let refreshed = try JSONDecoder().decode(
            Question.self,
            from: Data(#"{"id":"q1","type":"code","name":"Old","languages":["python"]}"#.utf8)
        )
        var overlay = QuestionEditOverlay()
        overlay.merge(QuestionMetadataChanges(name: "Renamed"))

        #expect(overlay.applying(to: original).name == "Renamed")
        #expect(overlay.applying(to: refreshed).languages == ["python"])
    }

    @Test func `system prompt edits survive overlays and metadata refreshes`() throws {
        let original = Question(id: "q1", type: "fullstack", name: "Project", customSystemPrompt: "Old")
        let prompt = "  Give hints.\nDo not solve.  "
        var overlay = QuestionEditOverlay()
        overlay.merge(QuestionMetadataChanges(customSystemPrompt: prompt))
        overlay.merge(QuestionMetadataChanges(name: "Renamed", tags: ["project"]))
        #expect(overlay.applying(to: original).customSystemPrompt == prompt)
        let metadata = try JSONDecoder().decode(QuestionDetailMetadata.self, from: Data(
            #"{"custom_system_prompt":"Remote"}"#.utf8
        ))
        #expect(overlay.applying(to: metadata.applying(to: original)).customSystemPrompt == prompt)
        overlay.merge(QuestionMetadataChanges(customSystemPrompt: ""))
        #expect(overlay.applying(to: original).customSystemPrompt?.isEmpty == true)
    }

    @Test func `detail request identity includes account and question`() {
        let accountA = UUID()
        let accountB = UUID()
        let original = QuestionDetailRequestIdentity(accountID: accountA, questionID: "q1")

        #expect(original != QuestionDetailRequestIdentity(accountID: accountB, questionID: "q1"))
        #expect(original != QuestionDetailRequestIdentity(accountID: accountA, questionID: "q2"))
        #expect(original == QuestionDetailRequestIdentity(accountID: accountA, questionID: "q1"))
    }
}
