//
//  CollectionPresentationTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

@MainActor
struct CollectionPresentationTests {
    @Test func `audit change labels do not change interview scheduling labels`() {
        #expect(NativeRecordPresentation.label("from", style: .audit) == "Before")
        #expect(NativeRecordPresentation.label("to", style: .audit) == "After")
        #expect(NativeRecordPresentation.label("from", style: .general) == "Starts")
        #expect(NativeRecordPresentation.label("to", style: .general) == "Ends")
        #expect(NativeRecordPresentation.label("ip_address", style: .audit) == "IP Address")
    }

    @Test func `section names do not become assessment types`() throws {
        let data = Data(#"""
        {"id":"t1","name":"Assessment","sections":[
            {"name":"Untitled","questions":2},{"name":"Coding","questions":3},{}
        ]}
        """#.utf8)
        let test = try JSONDecoder().decode(Test.self, from: data)
        #expect(test.presentationTypes.isEmpty)
        let sections = try #require(test.sections)
        #expect(sections.enumerated().map { $0.element.presentationTitle(index: $0.offset) }
            == ["Section 1", "Coding", "Section 3"])
        #expect(sections[0].questionCount == 2)
    }

    @Test func `explicit assessment types remain visible`() throws {
        let test = try JSONDecoder().decode(Test.self, from: Data(
            #"{"id":"t1","name":"Assessment","type":"role_based","sections":[{"name":"Coding"}]}"#.utf8
        ))
        #expect(test.presentationTypes == ["Role Based"])
    }

    @Test func `audit rows include resource identity and a readable timestamp`() {
        let event = NativeBusinessRecord(id: "event-1", value: .object([
            "action": .string("update"), "source_type": .string("Interview"), "source_id": .int(42),
            "created_at": .string("2026-11-08T09:30:00.500Z")
        ]))
        #expect(event.auditTitle == "Update · Interview 42")
        #expect(event.auditDate != nil)
        #expect(event.auditDate != "2026-11-08T09:30:00.500Z")
    }

    @Test func `filter edits and reset preserve the visible candidate query`() throws {
        let existing = [URLQueryItem(name: "query", value: "Synthetic Candidate"),
                        URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "offset", value: "10")]
        let draft = try NativeListFilters.draft(operationID: "api_search_candidates", query: existing,
                                                excluding: ["query"])
        #expect(!draft.parameters.contains { $0.name == "query" })
        let limit = try #require(draft.parameters.first { $0.name == "limit" })
        limit.text = "25"
        let applied = try NativeListFilters.applying(draft.request().query, to: existing, preserving: ["query"])
        #expect(applied.filter { $0.name == "query" } == [existing[0]])
        #expect(applied.contains(URLQueryItem(name: "limit", value: "25")))
        #expect(applied.contains(URLQueryItem(name: "offset", value: "10")))
        #expect(NativeListFilters.applying([], to: applied, preserving: ["query"]) == [existing[0]])
    }
}
