//
//  TemplatesTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Synthetic paginated endpoints distinguish ownership, template type and credentials.
private final class TemplateBrowserURLProtocol: URLProtocol {
    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = components?.queryItems ?? []
        let offset = query.first { $0.name == "offset" }?.value == "1" ? 1 : 0
        let filter = query.first { $0.name == "filter" }?.value ?? "all"
        let token = request.value(forHTTPHeaderField: "Authorization")
        let owner = token == "Bearer synthetic-alpha" ? "Alpha" : "Beta"
        let denied = token == "Bearer synthetic-denied"
        let body: String
        if url.path == "/x/api/v3/interview_templates" {
            let next = offset == 0
                ? "\"https://www.hackerrank.com/x/api/v3/interview_templates?offset=1&filter=\(filter)\""
                : "null"
            body = """
            {"data":[{"id":\(offset + 1),"name":"\(owner) \(filter) \(offset + 1)"}],"next":\(next),"total":2}
            """
        } else if url.path == "/x/api/v3/templates" {
            body = #"{"data":[{"id":"email-1","name":"Invite","subject":"Welcome"}],"next":null}"#
        } else if url.path.hasPrefix("/x/api/v3/interview_templates/") {
            body = """
            {"id":1,"name":"\(owner) full template","questions":["q2","q1"],"editor_access":false}
            """
        } else if url.path.hasPrefix("/x/api/v3/questions/") {
            let id = url.lastPathComponent == "mismatched" ? "other-question" : url.lastPathComponent
            body = """
            {"id":"\(id)","name":"\(owner) question","type":"coding"}
            """
        } else {
            body = #"{"id":"email-1","name":"Invite","content":"<p>Full email body</p>","default":true}"#
        }
        guard let response = HTTPURLResponse(url: url, statusCode: denied ? 403 : 200,
                                             httpVersion: "HTTP/1.1", headerFields: nil) else { return }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
struct TemplatesTests {
    private func client(_ account: Account) -> HackerRankClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TemplateBrowserURLProtocol.self]
        return HackerRankClient(account: account, session: URLSession(configuration: configuration))
    }

    @Test func `interview filters and pagination reach the SDK transport`() async throws {
        let client = client(Account(label: "Alpha", token: "synthetic-alpha"))
        let first = try await TemplateLibrary.page(client: client, kind: .interview, ownership: .shared, cursor: nil)
        #expect(first.items.map(\.title) == ["Alpha shared 1"])
        #expect(first.totalCount == 2)
        let cursor = try #require(first.next)
        let second = try await TemplateLibrary.page(
            client: client, kind: .interview, ownership: .shared, cursor: cursor
        )
        #expect(second.items.map(\.apiID) == ["2"])
        #expect(second.items.first?.title == "Alpha shared 2")
        #expect(second.next == nil)
        let owned = try await TemplateLibrary.page(client: client, kind: .interview, ownership: .owned, cursor: nil)
        #expect(owned.items.first?.title == "Alpha owned 1")
        let all = try await TemplateLibrary.page(client: client, kind: .interview, ownership: .all, cursor: nil)
        #expect(all.items.first?.title == "Alpha all 1")
    }

    @Test func `show endpoints supply question membership and full email content`() async throws {
        let client = client(Account(label: "Alpha", token: "synthetic-alpha"))
        let summary = TemplateRecord(interview: InterviewTemplate(id: 1, name: "Summary"))
        let detail = try await TemplateLibrary.detail(summary, client: client)
        #expect(detail.title == "Alpha full template")
        #expect(detail.questionIDs == ["q2", "q1"])
        #expect(detail.editorAccess == false)
        let invitations = try await TemplateLibrary.page(
            client: client, kind: .invitation, ownership: .all, cursor: nil
        )
        let invitation = try #require(invitations.items.first)
        #expect(invitation.kind == .invitation)
        #expect(invitation.subject == "Welcome")
        let email = try await TemplateLibrary.detail(invitation, client: client)
        #expect(email.content == "<p>Full email body</p>")
        #expect(email.isDefault == true)
    }

    @Test func `merged pagination and detail retain the originating account`() async throws {
        let accounts = [
            Account(label: "Alpha", token: "synthetic-alpha"),
            Account(label: "Beta", token: "synthetic-beta")
        ]
        let first = try await MergedLoader.page(accounts: accounts, cursor: nil) { account, cursor in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [TemplateBrowserURLProtocol.self]
            return try await TemplateLibrary.page(
                client: HackerRankClient(account: account, session: URLSession(configuration: configuration)),
                kind: .interview, ownership: .all, cursor: cursor
            )
        }
        #expect(first.items.map(\.item.apiID) == ["1", "1"])
        #expect(Set(first.items.map(\.id)).count == 2)
        let beta = try #require(first.items.last)
        let detail = try await TemplateLibrary.detail(beta.item, client: client(beta.account))
        #expect(detail.title == "Beta full template")
        let cursor = try #require(first.next)
        let second = try await MergedLoader.page(accounts: accounts, cursor: cursor) { account, next in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [TemplateBrowserURLProtocol.self]
            return try await TemplateLibrary.page(
                client: HackerRankClient(account: account, session: URLSession(configuration: configuration)),
                kind: .interview, ownership: .all, cursor: next
            )
        }
        #expect(second.items.map(\.item.apiID) == ["2", "2"])
        #expect(second.next == nil)
    }

    @Test func `missing identifiers remain visible and cached membership stays exact`() async throws {
        let unnamed = TemplateRecord(interview: InterviewTemplate())
        let other = TemplateRecord(interview: InterviewTemplate())
        #expect(unnamed.id != other.id)
        #expect(unnamed.apiID == nil)
        #expect(unnamed.title == "Unnamed Interview Template")
        let unchanged = try await TemplateLibrary.detail(
            unnamed, client: client(Account(label: "A", token: "synthetic-denied"))
        )
        #expect(unchanged == unnamed)
        let record = TemplateRecord(interview: InterviewTemplate(id: 1, name: "   ", questions: ["q2", "q1"]))
        #expect(record.title == "Interview Template 1")
        let restored = try JSONDecoder().decode(TemplateRecord.self, from: JSONEncoder().encode(record))
        #expect(restored == record)
        #expect(restored.questionIDs == ["q2", "q1"])
        #expect(TemplateRecord(interview: InterviewTemplate(id: 2, questions: [])).subtitle == "0 questions")
        #expect(unnamed.questionIDs == nil)
    }

    @Test func `request failures propagate to the list error state`() async {
        let denied = client(Account(label: "Denied", token: "synthetic-denied"))
        await #expect(throws: HackerRankError.self) {
            try await TemplateLibrary.page(client: denied, kind: .interview, ownership: .all, cursor: nil)
        }
    }

    @Test func `both template browsers work with the bundled demo backend`() async throws {
        let demo = HackerRankClient(account: .demo)
        let interviews = try await TemplateLibrary.page(client: demo, kind: .interview, ownership: .all, cursor: nil)
        #expect(interviews.items.map(\.title) == ["Backend Pairing", "Frontend Pairing"])
        let invitations = try await TemplateLibrary.page(client: demo, kind: .invitation, ownership: .all, cursor: nil)
        #expect(invitations.items.map(\.title) == ["Default Invite", "Reminder"])
        #expect(invitations.items.first?.isDefault == true)
    }

    @Test func `cached ownership views stay separate and invitation caches ignore interview filters`() {
        let accountID = UUID()
        let all = TemplateLibrary.cacheKey(accountID: accountID, kind: .interview, ownership: .all)
        let shared = TemplateLibrary.cacheKey(accountID: accountID, kind: .interview, ownership: .shared)
        #expect(all != shared)
        #expect(all != TemplateLibrary.cacheKey(accountID: UUID(), kind: .interview, ownership: .all))
        #expect(TemplateLibrary.cacheKey(accountID: accountID, kind: .invitation, ownership: .all)
            == TemplateLibrary.cacheKey(accountID: accountID, kind: .invitation, ownership: .shared))
    }

    @Test func `opening a template question never substitutes a different question`() async throws {
        let client = client(Account(label: "Alpha", token: "synthetic-alpha"))
        let question = try await TemplateLibrary.question(id: "q1", client: client)
        #expect(question.id == "q1")
        #expect(question.name == "Alpha question")
        await #expect(throws: HackerRankError.self) {
            try await TemplateLibrary.question(id: "mismatched", client: client)
        }
    }
}
