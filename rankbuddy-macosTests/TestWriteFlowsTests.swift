import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the test CRUD write flows (#57) — create, rename, delete — driven through
/// the demo server (a POST is acknowledged with a created record, a PATCH/DELETE with a 200,
/// and the bad-key token 401s). Serialized because the body-capture assertions read the
/// mock's per-path captured body.
@MainActor
@Suite(.serialized)
struct TestWriteFlowsTests {
    private func makeClient(token: String = Account.demoToken) -> HackerRankClient {
        HackerRankClient(account: Account(label: "Demo", token: token))
    }

    @Test func `creating a test posts the name and decodes the created record`() async throws {
        let path = "/x/api/v3/tests"
        MockHackerRankURLProtocol.resetCapturedBody(forPath: path)
        let created = try await makeClient().createTest(name: "  Backend Screen  ")
        #expect(created.id == "t-created")

        let body = try #require(MockHackerRankURLProtocol.lastRequestBody(forPath: path))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["name"] as? String == "Backend Screen")
    }

    @Test func `renaming a test patches the new name under its id`() async throws {
        let path = "/x/api/v3/tests/t1"
        MockHackerRankURLProtocol.resetCapturedBody(forPath: path)
        let updated = try await makeClient().updateTest(testID: "t1", name: "  Renamed Screen  ")
        #expect(updated.id == "t-created")

        let body = try #require(MockHackerRankURLProtocol.lastRequestBody(forPath: path))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["name"] as? String == "Renamed Screen")
    }

    @Test func `deleting a test removes it against the demo without throwing`() async throws {
        // The test is identified in the path; a 2xx is enough to confirm the wiring.
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
