//
//  TestDetailTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the richer single-test read (#105): `TestDetail`'s resilient decoding and the
/// client method that fetches it through the demo server.
@MainActor
struct TestDetailTests {
    private func makeClient() -> HackerRankClient {
        HackerRankClient(account: Account(label: "Demo", token: Account.demoToken))
    }

    @Test func `detail decodes through the client`() async throws {
        let detail = try await makeClient().test(id: "t1")
        #expect(detail.shortLoginURL?.isEmpty == false)
        #expect(detail.publicLoginURL?.contains("login") == true)
        #expect(detail.accessPassword == "demo-master-pw")
        #expect(detail.mcqCorrectScore == 4.0)
        #expect(detail.mcqIncorrectScore == -1.0)
        #expect(detail.hasAccess)
        #expect(detail.hasScoring)
    }

    @Test func `detail tolerates a test with no extra fields`() throws {
        let json = #"{"id":"t9","name":"Bare Test"}"#
        let detail = try JSONDecoder().decode(TestDetail.self, from: Data(json.utf8))
        #expect(detail.shortLoginURL == nil)
        #expect(detail.accessPassword == nil)
        #expect(detail.hasAccess == false)
        #expect(detail.hasScoring == false)
    }

    @Test func `the single-test route is distinct from the list route`() async throws {
        // The list paginates (first page of three); the single read returns the detailed test,
        // proving the mock routes "/tests/{id}" separately from "/tests".
        let list = try await makeClient().testsPage()
        #expect(list.items.count == 3)
        let detail = try await makeClient().test(id: "t1")
        #expect(detail.hasAccess)
    }
}
