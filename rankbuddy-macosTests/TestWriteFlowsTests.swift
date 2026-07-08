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
