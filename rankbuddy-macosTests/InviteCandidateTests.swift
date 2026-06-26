import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the invite-candidate write flow (#12), driven through the in-process demo
/// server. The mock acknowledges a `POST` under the success scenario with a created record
/// and 401s the bad-key token, so these exercise the client's write path end-to-end: the
/// `POST` to `/tests/{id}/candidates`, the decode of the created candidate, and the
/// unauthorized path.
@MainActor
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

    @Test func `the write-actions opt-in defaults to read-only`() {
        // The key is shared by the Settings toggle and the views that gate the invite UI;
        // unset means read-only.
        let key = WriteActions.defaultsKey
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: key)
        defaults.removeObject(forKey: key)
        #expect(defaults.bool(forKey: key) == false)
        // Restore whatever the environment had, so the test leaves no trace.
        if let original { defaults.set(original, forKey: key) }
    }
}
