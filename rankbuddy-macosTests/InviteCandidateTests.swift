import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the invite-candidate write flow (#12), driven through the in-process demo
/// server. The mock acknowledges a `POST` under the success scenario with a created record
/// and 401s the bad-key token, so these exercise the client's write path end-to-end: the
/// `POST` to `/tests/{id}/candidates`, the decode of the created candidate, and the
/// unauthorized path.
/// Serialized because the body-capture assertions read a shared static on the mock; without
/// it, Swift Testing's parallel execution lets one invite's body leak into another's check.
@MainActor
@Suite(.serialized)
struct InviteCandidateTests {
    private func makeClient(token: String = Account.demoToken) -> HackerRankClient {
        HackerRankClient(account: Account(label: "Demo", token: token))
    }

    @Test func `inviting a candidate posts and decodes the created record`() async throws {
        let created = try await makeClient().inviteCandidate(testID: "t1", email: "new@example.com")
        // The success scenario answers a POST with the canned created-candidate fixture.
        #expect(created.id == "c-invited")
    }

    @Test func `a blank full name and an email-less send still succeed`() async throws {
        // Optional fields: a blank name is dropped from the body, and the email toggle off
        // is a valid request. The mock acknowledges either way.
        let created = try await makeClient().inviteCandidate(
            testID: "t1",
            email: "  trimmed@example.com  ",
            fullName: "   ",
            sendEmail: false
        )
        #expect(created.id == "c-invited")
    }

    @Test func `the invite body is snake-cased with the entered fields`() async throws {
        let path = "/x/api/v3/tests/t1/candidates"
        MockHackerRankURLProtocol.resetCapturedBody(forPath: path)
        _ = try await makeClient().inviteCandidate(
            testID: "t1",
            email: "  new@example.com ",
            fullName: "New Person",
            sendEmail: true
        )
        let body = try #require(MockHackerRankURLProtocol.lastRequestBody(forPath: path))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        // The email is trimmed and the API's snake-case keys are used.
        #expect(json?["email"] as? String == "new@example.com")
        #expect(json?["full_name"] as? String == "New Person")
        #expect(json?["send_email"] as? Bool == true)
    }

    @Test func `a blank name is omitted from the invite body`() async throws {
        let path = "/x/api/v3/tests/t1/candidates"
        MockHackerRankURLProtocol.resetCapturedBody(forPath: path)
        _ = try await makeClient().inviteCandidate(
            testID: "t1",
            email: "new@example.com",
            fullName: "   ",
            sendEmail: false
        )
        let body = try #require(MockHackerRankURLProtocol.lastRequestBody(forPath: path))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        // A whitespace-only name is dropped entirely rather than sent empty.
        #expect(json?["full_name"] == nil)
        #expect(json?["send_email"] as? Bool == false)
    }

    @Test func `inviting against the bad-key account surfaces the server's 401`() async {
        let client = HackerRankClient(account: .badKeyDemo)
        do {
            _ = try await client.inviteCandidate(testID: "t1", email: "new@example.com")
            Issue.record("expected an unauthorized error")
        } catch let error as HackerRankError {
            guard case let .http(status, _) = error else {
                Issue.record("expected .http, got \(error)")
                return
            }

            #expect(status == 401)
        } catch {
            Issue.record("expected HackerRankError, got \(error)")
        }
    }
}
