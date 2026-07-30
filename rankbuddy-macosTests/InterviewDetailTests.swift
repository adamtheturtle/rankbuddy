//
//  InterviewDetailTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the single-interview reads (#103): the `InterviewDetail`/`InterviewTranscript`
/// models' resilient decoding and the client methods that fetch them through the demo server.
@MainActor
struct InterviewDetailTests {
    private func makeClient() -> HackerRankClient {
        HackerRankClient(account: Account(label: "Demo", token: Account.demoToken))
    }

    // MARK: - Client routing

    @Test func `interview detail decodes through the client`() async throws {
        let detail = try await makeClient().interview(id: "i1")
        #expect(detail.scheduledFrom != nil)
        #expect(detail.resultURL?.contains("/result") == true)
        #expect(detail.candidate?.displayName == "Ada Lovelace")
        #expect(detail.interviewers.count == 2)
        #expect(detail.interviewers.contains { $0.email == "ian@example.com" })
    }

    @Test func `interview transcript decodes through the client`() async throws {
        let transcript = try await makeClient().interviewTranscript(id: "i1")
        #expect(transcript.messages.count == 3)
        #expect(transcript.messages.first?.candidate == false)
        #expect(transcript.messages.contains { $0.candidate == true })
        #expect(transcript.messages.first?.messageID == "m1")
    }

    // MARK: - Person decoding (string vs object shapes)

    @Test func `interviewer decodes from a keyed object`() throws {
        let json = #"{"firstname":"Ian","lastname":"Interviewer","email":"ian@example.com"}"#
        let person = try JSONDecoder().decode(InterviewPerson.self, from: Data(json.utf8))
        #expect(person.displayName == "Ian Interviewer")
        #expect(person.email == "ian@example.com")
    }

    @Test func `interviewer decodes from a bare email string`() throws {
        let json = #""ian@example.com""#
        let person = try JSONDecoder().decode(InterviewPerson.self, from: Data(json.utf8))
        #expect(person.email == "ian@example.com")
        #expect(person.displayName == "ian@example.com")
    }

    @Test func `interviewer decodes from a bare name string`() throws {
        let json = #""Ian Interviewer""#
        let person = try JSONDecoder().decode(InterviewPerson.self, from: Data(json.utf8))
        #expect(person.name == "Ian Interviewer")
        #expect(person.email == nil)
        #expect(person.displayName == "Ian Interviewer")
    }

    // MARK: - Resilience

    @Test func `detail tolerates missing optional fields`() throws {
        // A sparse detail (only the base list fields) must still decode without throwing.
        let json = #"{"id":"i9","status":"scheduled","url":"https://example.com/i9"}"#
        let detail = try JSONDecoder().decode(InterviewDetail.self, from: Data(json.utf8))
        #expect(detail.scheduledFrom == nil)
        #expect(detail.interviewers.isEmpty)
        #expect(detail.hasPeople == false)
    }

    @Test func `transcript tolerates a missing messages array`() throws {
        let detail = try JSONDecoder().decode(InterviewTranscript.self, from: Data("{}".utf8))
        #expect(detail.messages.isEmpty)
    }

    @Test func `scheduled interview end must follow its start`() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        #expect(InterviewDetailView.isValidSchedule(start: start, end: start.addingTimeInterval(1)))
        #expect(!InterviewDetailView.isValidSchedule(start: start, end: start))
        #expect(!InterviewDetailView.isValidSchedule(start: start, end: start.addingTimeInterval(-1)))
    }

    @Test func `detail request identity includes account and interview`() {
        let accountA = UUID()
        let accountB = UUID()
        let original = InterviewDetailRequestIdentity(accountID: accountA, interviewID: "i1")

        #expect(original != InterviewDetailRequestIdentity(accountID: accountB, interviewID: "i1"))
        #expect(original != InterviewDetailRequestIdentity(accountID: accountA, interviewID: "i2"))
        #expect(original == InterviewDetailRequestIdentity(accountID: accountA, interviewID: "i1"))
    }

    @Test func `merged interview detail uses its explicit originating account`() {
        let explicit = Account(label: "Origin", token: "origin")
        let current = Account(label: "Other", token: "other")

        #expect(InterviewDetailAccountResolution.resolve(
            explicit: explicit,
            current: current,
            isMerged: true
        )?.id == explicit.id)
        #expect(InterviewDetailAccountResolution.resolve(
            explicit: nil,
            current: current,
            isMerged: true
        ) == nil)
    }
}
