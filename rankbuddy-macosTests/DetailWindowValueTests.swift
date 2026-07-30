//
//  DetailWindowValueTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the open-in-new-window value (#49): it round-trips through Codable (so it can
/// pass through openWindow) and titles the window.
@MainActor
struct DetailWindowValueTests {
    private func test(name: String) throws -> HackerRankKit.Test {
        try JSONDecoder().decode(HackerRankKit.Test.self, from: Data(#"{"id":"t1","name":"\#(name)"}"#.utf8))
    }

    @Test func `it round-trips through Codable`() throws {
        let value = try DetailWindowValue.test(test(name: "Backend Screen"), accountID: nil)
        let data = try JSONEncoder().encode(value)
        let restored = try JSONDecoder().decode(DetailWindowValue.self, from: data)
        #expect(restored == value)
    }

    @Test func `the window title comes from the item`() throws {
        #expect(try DetailWindowValue.test(test(name: "Backend Screen"), accountID: nil).windowTitle
            == "Backend Screen")
    }

    @Test func `removed explicit account does not fall back to current account`() {
        let current = Account(label: "Current", token: "token")
        #expect(DetailWindowAccountResolution.resolve(
            id: UUID(),
            accounts: [current],
            current: current
        ) == nil)
        #expect(DetailWindowAccountResolution.resolve(
            id: nil,
            accounts: [current],
            current: current
        )?.id == current.id)
    }

    @Test func `standalone user persists identity and originating account`() throws {
        let accountID = UUID()
        let value = DetailWindowValue.user(
            userID: "u1",
            userName: "Ada Lovelace",
            accountID: accountID
        )
        let data = try JSONEncoder().encode(value)
        let restored = try JSONDecoder().decode(DetailWindowValue.self, from: data)

        guard case let .user(userID, userName, restoredAccountID) = restored else {
            Issue.record("expected a user detail value")
            return
        }

        #expect(userID == "u1")
        #expect(userName == "Ada Lovelace")
        #expect(restoredAccountID == accountID)
        #expect(try #require(String(data: data, encoding: .utf8)).contains("email") == false)
    }

    @Test func `standalone team persists identity instead of a stale snapshot`() throws {
        let accountID = UUID()
        let value = DetailWindowValue.team(
            teamID: "team-1",
            teamName: "Platform",
            accountID: accountID
        )
        let data = try JSONEncoder().encode(value)
        let restored = try JSONDecoder().decode(DetailWindowValue.self, from: data)

        #expect(restored == value)
        #expect(value.windowTitle == "Platform")
        #expect(try #require(String(data: data, encoding: .utf8)).contains("departments") == false)
    }

    @Test func `standalone candidate persists only opaque lookup identifiers`() throws {
        let value = DetailWindowValue.candidate(
            testID: "test-1",
            candidateID: "candidate-1",
            accountID: UUID()
        )
        let data = try JSONEncoder().encode(value)
        let encoded = try #require(String(data: data, encoding: .utf8))

        #expect(try JSONDecoder().decode(DetailWindowValue.self, from: data) == value)
        #expect(value.windowTitle == "Candidate")
        #expect(!encoded.contains("email"))
        #expect(!encoded.contains("score"))
        #expect(!encoded.contains("feedback"))
    }

    @Test func `standalone interview preserves its originating account`() throws {
        let interview = try JSONDecoder().decode(
            Interview.self,
            from: Data(#"{"id":"i1","title":"Pairing","status":"scheduled"}"#.utf8)
        )
        let accountID = UUID()
        let value = DetailWindowValue.interview(interview, accountID: accountID)
        let restored = try JSONDecoder().decode(
            DetailWindowValue.self,
            from: JSONEncoder().encode(value)
        )

        guard case let .interview(_, restoredAccountID) = restored else {
            Issue.record("expected an interview detail value")
            return
        }

        #expect(restoredAccountID == accountID)
    }
}
