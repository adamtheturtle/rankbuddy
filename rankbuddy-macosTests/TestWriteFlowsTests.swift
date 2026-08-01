//
//  TestWriteFlowsTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the test CRUD write flows (#57) — create, rename, delete — driven through
/// the in-process demo server (`HackerRankClient.mock()`, reached via the `Account`
/// convenience initializer). A write is acknowledged with the canned echo record, and the
/// bad-token account answers 401. The exact request-body shaping (trimming, snake_case) is
/// the client's responsibility and is covered in `HackerRankKit`'s own tests.
@MainActor
struct TestWriteFlowsTests {
    @Test func `names respect the API limit`() {
        #expect(TestNameValidation.isValid("Backend Screen"))
        #expect(!TestNameValidation.isValid(String(repeating: "x", count: 256)))
    }

    @Test func `rename submission requires a normalized change`() {
        #expect(!TestNameValidation.canSubmit(" Backend Screen ", currentName: "Backend Screen"))
        #expect(!TestNameValidation.canSubmit("   ", currentName: "Backend Screen"))
        #expect(TestNameValidation.canSubmit("Renamed Screen", currentName: " Backend Screen "))
        #expect(TestNameValidation.canSubmit("New Test", currentName: nil))
    }

    @Test func `assessment numbers have product ceilings`() {
        #expect(TestAssessmentValidation.error(duration: "1", cutoffScore: "0") == nil)
        #expect(TestAssessmentValidation.error(duration: " 1440\n", cutoffScore: "1000000") == nil)
        #expect(TestAssessmentValidation.error(duration: "0", cutoffScore: "0") != nil)
        #expect(TestAssessmentValidation.error(duration: "1441", cutoffScore: "0") != nil)
        #expect(TestAssessmentValidation.error(duration: "30", cutoffScore: "1000001") != nil)
    }

    @Test func `unchanged assessment booleans stay absent from updates`() {
        #expect(TestBooleanEditing.updateValue(false, changed: false) == nil)
        #expect(TestBooleanEditing.updateValue(true, changed: false) == nil)
        #expect(TestBooleanEditing.updateValue(false, changed: true) == false)
        #expect(TestBooleanEditing.updateValue(true, changed: true) == true)
    }

    @Test func `assessment schedule accepts an ordered ISO window`() {
        #expect(TestScheduleValidation.error(
            startTime: "2026-08-01T09:00:00Z",
            endTime: "2026-08-02T09:00:00Z"
        ) == nil)
        #expect(TestScheduleValidation.error(
            startTime: "2026-08-01T09:00:00.123Z",
            endTime: "2026-08-01T09:00:00.456Z"
        ) == nil)
    }

    @Test func `assessment schedule rejects malformed and reversed windows`() {
        #expect(TestScheduleValidation.error(startTime: "tomorrow", endTime: "") != nil)
        #expect(TestScheduleValidation.error(
            startTime: "2026-08-02T09:00:00Z",
            endTime: "2026-08-01T09:00:00Z"
        ) != nil)
        #expect(TestScheduleValidation.error(
            startTime: "2026-08-01T09:00:00Z",
            endTime: "2026-08-01T09:00:00Z"
        ) != nil)
    }

    private func makeClient(token: String = Account.demoToken) -> HackerRankClient {
        HackerRankClient(account: Account(label: "Demo", token: token))
    }

    @Test func `creating a test decodes the created record`() async throws {
        let created = try await makeClient().createTest(name: "  Backend Screen  ")
        #expect(created.id == "t-created")
    }

    @Test func `renaming a test decodes the created record`() async throws {
        let updated = try await makeClient().updateTest(testID: "t1", name: "  Renamed Screen  ")
        #expect(updated.id == "t-created")
    }

    @Test func `creating and updating tests accepts richer options`() async throws {
        let options = TestWriteOptions(
            duration: 90,
            cutoffScore: 70,
            instructions: "Complete every question.",
            startTime: "2026-08-01T09:00:00Z",
            endTime: "2026-08-02T09:00:00Z",
            languages: ["swift"],
            tags: ["backend"],
            shuffleQuestions: true,
            enableProctoring: true
        )
        #expect(try await makeClient().createTest(name: "Backend", options: options).id == "t-created")
        #expect(try await makeClient().updateTest(testID: "t1", name: "Backend", options: options).id == "t-created")
    }

    @Test func `deleting a test succeeds against the demo without throwing`() async throws {
        let deleted = try await makeClient().deleteTest(testID: "t1")
        #expect(deleted.id == "t-created")
    }

    @Test func `writes against the bad-key account surface the server's 401`() async {
        let client = HackerRankClient(account: .badKeyDemo)
        await #expect(throws: HackerRankError.self) {
            try await client.createTest(name: "Nope")
        }
        await #expect(throws: HackerRankError.self) {
            try await client.updateTest(testID: "t1", name: "Nope")
        }
        await #expect(throws: HackerRankError.self) {
            try await client.deleteTest(testID: "t1")
        }
    }
}
