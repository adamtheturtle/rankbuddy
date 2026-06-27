import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the interview write flows (#60) — create a QuickPad and schedule an
/// interview — driven through the demo server (a POST is acknowledged with a created
/// interview record and the bad-key token 401s). Serialized because the body-capture
/// assertions read the mock's per-path captured body.
@MainActor
@Suite(.serialized)
struct InterviewWriteFlowsTests {
    private let path = "/x/api/v3/interviews"

    private func makeClient(token: String = Account.demoToken) -> HackerRankClient {
        HackerRankClient(account: Account(label: "Demo", token: token))
    }

    @Test func `creating a QuickPad posts the quickpad flag and decodes the created record`() async throws {
        MockHackerRankURLProtocol.resetCapturedBody(forPath: path)
        let created = try await makeClient().createQuickPad(title: "  Pairing Pad  ")
        #expect(created.id == "i-created")
        #expect(created.url?.contains("i-created") == true)

        let body = try #require(MockHackerRankURLProtocol.lastRequestBody(forPath: path))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["quickpad"] as? Bool == true)
        #expect(json?["title"] as? String == "Pairing Pad")
    }

    @Test func `a blank QuickPad title is omitted from the body`() async throws {
        MockHackerRankURLProtocol.resetCapturedBody(forPath: path)
        _ = try await makeClient().createQuickPad(title: "   ")
        let body = try #require(MockHackerRankURLProtocol.lastRequestBody(forPath: path))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["title"] == nil)
        #expect(json?["quickpad"] as? Bool == true)
    }

    @Test func `scheduling posts the title, an ISO start time, and the candidate`() async throws {
        MockHackerRankURLProtocol.resetCapturedBody(forPath: path)
        // A fixed instant so the encoded ISO-8601 string is deterministic.
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        _ = try await makeClient().scheduleInterview(
            title: "  Backend Screen  ",
            from: start,
            candidateEmail: " ada@example.com ",
            notes: "  Focus on systems design  "
        )

        let body = try #require(MockHackerRankURLProtocol.lastRequestBody(forPath: path))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["title"] as? String == "Backend Screen")
        #expect(json?["candidate"] as? String == "ada@example.com")
        #expect(json?["notes"] as? String == "Focus on systems design")
        // The start time round-trips as an ISO-8601 string.
        let from = try #require(json?["from"] as? String)
        #expect(ISO8601DateFormatter().date(from: from) == start)
    }

    @Test func `a blank candidate and notes are omitted when scheduling`() async throws {
        MockHackerRankURLProtocol.resetCapturedBody(forPath: path)
        _ = try await makeClient().scheduleInterview(title: "Solo Pad", from: Date(timeIntervalSince1970: 0))
        let body = try #require(MockHackerRankURLProtocol.lastRequestBody(forPath: path))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["candidate"] == nil)
        #expect(json?["notes"] == nil)
    }

    @Test func `interview writes against the bad-key account surface the server's 401`() async {
        let client = HackerRankClient(account: .badKeyDemo)
        await #expect(throws: HackerRankError.self) {
            try await client.createQuickPad(title: "Nope")
        }
        await #expect(throws: HackerRankError.self) {
            try await client.scheduleInterview(title: "Nope", from: Date(timeIntervalSince1970: 0))
        }
    }
}
