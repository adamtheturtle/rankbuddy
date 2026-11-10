//
//  NativeFeatureFormTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Synchronization
import Testing

private nonisolated enum NativeContractCases {
    static var operationIDs: [String] {
        (try? HackerRankClient.apiCatalogue().operations.map(\.id)) ?? []
    }
}

private final nonisolated class NativeRequestCapture: URLProtocol {
    static let requests = Mutex<[URLRequest]>([])
    static let status = Mutex(200)
    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: Self.status.withLock { $0 },
                                             httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"])
        else { return }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
@MainActor
struct NativeFeatureFormTests {
    private func client() throws -> HackerRankClient {
        NativeRequestCapture.requests.withLock { $0 = [] }
        NativeRequestCapture.status.withLock { $0 = 200 }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NativeRequestCapture.self]
        return try HackerRankClient(token: "synthetic-v3", baseURL: #require(URL(string: "https://example.test")),
                                    session: URLSession(configuration: config))
    }

    /// Exercise the actual native form state and its SDK transport, independently of MCP.
    @Test(arguments: NativeContractCases.operationIDs)
    func `native controls preserve every documented request field`(operationID: String) async throws {
        let client = try client()
        let draft = try NativeFeatureFormModel(operationID: operationID)
        for field in draft.parameters {
            fill(field)
        }
        if let body = draft.body {
            fill(body)
        }
        if ["api_create_question", "api_update_question"].contains(operationID) {
            // This exhaustive fixture includes a custom prompt, which only fullstack supports.
            draft.body?.children.first { $0.name == "type" }?.text = QuestionType.fullstack.rawValue
        }
        let request = try draft.request()
        #expect(await draft.submit(client: client, scimToken: "synthetic-provisioning"))
        let sent = try #require(NativeRequestCapture.requests.withLock { $0.last })
        #expect(sent.httpMethod == draft.operation.method)
        #expect(sent.value(forHTTPHeaderField: "Authorization")
            == "Bearer \(draft.operation.scim ? "synthetic-provisioning" : "synthetic-v3")")
        let query = try URLComponents(url: #require(sent.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        for parameter in draft.operation.parameters where parameter.location == "query" {
            #expect(query.contains { $0.name == parameter.name }, "\(operationID): \(parameter.name)")
        }
        if let body = request.body {
            let encoded = try readBody(sent)
            #expect(try HackerRankClient.makeDecoder().decode(HackerRankJSONValue.self, from: encoded) == body)
            let expected = NativeFormSchema.resolve(draft.operation.bodySchema ?? .object([:]),
                                                    catalogue: draft.catalogue).object["properties"]?.object.keys ?? [:]
                .keys
            #expect(Set(body.object.keys).isSuperset(of: Set(expected.map {
                draft.operation.scim && draft.operation.method == "PATCH" && $0 == "operations" ? "Operations" : $0
            })), "\(operationID)")
        }
    }

    @Test
    func `false zero empty list and empty text remain explicit values`() throws {
        let draft = try NativeFeatureFormModel(operationID: "api_update_test", path: ["id": "1"])
        let locked = try #require(draft.body?.children.first { $0.name == "locked" })
        locked.included = true
        locked.boolean = false
        let cutoff = try #require(draft.body?.children.first { $0.name == "cutoff_score" })
        cutoff.included = true
        cutoff.text = "0"
        let tags = try #require(draft.body?.children.first { $0.name == "tags" })
        tags.included = true
        let instructions = try #require(draft.body?.children.first { $0.name == "instructions" })
        instructions.included = true
        #expect(try draft.request().body == .object([
            "locked": .bool(false), "cutoff_score": .int(0), "tags": .array([]), "instructions": .string("")
        ]))
    }

    @Test
    func `editing one setting does not resend unchanged settings`() throws {
        let draft = try NativeFeatureFormModel(operationID: "api_update_test", path: ["id": "1"], initial: .object([
            "name": .string("Current Name"), "locked": .bool(true), "duration": .int(60)
        ]))
        let duration = try #require(draft.body?.children.first { $0.name == "duration" })
        duration.text = "90"
        #expect(try draft.request().body == .object(["duration": .int(90)]))
    }

    @Test
    func `provisioning email entries use objects and multiple choice answers use numbers`() throws {
        let user = try NativeFeatureFormModel(operationID: "api_scim_create_user")
        let emails = try #require(user.body?.children.first { $0.name == "emails" })
        emails.addEntry()
        let value = try #require(emails.entries.first?.children.first { $0.name == "value" })
        value.text = "person@example.test"
        #expect(try emails.value() == .array([.object(["value": .string("person@example.test")])]))
        let question = try NativeFeatureFormModel(operationID: "api_create_question")
        let answer = try #require(question.body?.children.first { $0.name == "answer" })
        answer.included = true
        answer.kind = "array"
        answer.addEntry()
        answer.entries[0].text = "2"
        #expect(try answer.value() == .array([.int(2)]))
    }

    @Test(arguments: ["api_create_question", "api_update_question"])
    func `question forms share SDK types and preserve numeric looking text answers`(operationID: String) throws {
        let draft = try NativeFeatureFormModel(operationID: operationID, path: ["question_id": "1"])
        let body = try #require(draft.body)
        let type = try #require(body.children.first { $0.name == "type" })
        #expect(type.choices.map(\.text) == QuestionType.allCases.map(\.rawValue))
        let answer = try #require(body.children.first { $0.name == "answer" })
        answer.included = true
        answer.kind = "string"
        answer.text = "0"
        #expect(try answer.value() == .string("0"))
    }

    @Test func `unsupported custom prompts fail before the native form writes`() async throws {
        let client = try client()
        let draft = try NativeFeatureFormModel(operationID: "api_update_question", path: ["question_id": "1"])
        let type = try #require(draft.body?.children.first { $0.name == "type" })
        type.included = true
        type.text = QuestionType.code.rawValue
        let prompt = try #require(draft.body?.children.first { $0.name == "custom_system_prompt" })
        prompt.included = true
        prompt.text = "Give hints."
        #expect(await !draft.submit(client: client, scimToken: nil))
        #expect(draft.error != nil)
        #expect(!draft.uncertain)
        #expect(NativeRequestCapture.requests.withLock { $0.isEmpty })
    }

    @Test
    func `an existing question type outside Swagger remains unchanged`() throws {
        let draft = try NativeFeatureFormModel(operationID: "api_update_question", path: ["question_id": "1"],
                                               initial: .object([
                                                   "type": .string("project"),
                                                   "name": .string("Project")
                                               ]))
        let name = try #require(draft.body?.children.first { $0.name == "name" })
        name.text = "Updated Project"
        #expect(try draft.request().body == .object(["name": .string("Updated Project")]))
    }

    @Test
    func `free-form nested settings preserve numeric boolean and null values`() throws {
        let catalogue = try HackerRankClient.apiCatalogue()
        let original: HackerRankJSONValue = .object(["enabled": .bool(false), "count": .int(0),
                                                     "ratio": .double(1.5), "empty": .null])
        let field = NativeFormField(
            catalogue: catalogue,
            name: "Metadata",
            schema: .object(["type": .string("object")]),
            required: true,
            value: original
        )
        #expect(try field.value() == original)
    }

    @Test
    func `an empty interviewer note is an explicit clear`() throws {
        let draft = try NativeFeatureFormModel(operationID: "api_update_interviewer_note", path: ["interview_id": "1"])
        #expect(try draft.request().body == .object(["content": .string("")]))
    }

    @Test
    func `SCIM patch uses the service capitalisation and patch schema`() throws {
        let draft = try NativeFeatureFormModel(operationID: "api_scim_edit_user_patch", path: ["id": "1"])
        let operations = try #require(draft.body?.children.first { $0.name == "operations" })
        operations.addEntry()
        let change = try #require(operations.entries.first)
        let operation = try #require(change.children.first { $0.name == "op" })
        operation.text = "replace"
        let value = try #require(change.children.first { $0.name == "value" })
        value.included = true
        value.kind = "object"
        value.addEntry()
        value.entries[0].name = "active"
        value.entries[0].kind = "boolean"
        value.entries[0].boolean = false
        let body = try #require(draft.request().body?.object)
        #expect(body["operations"] == nil)
        #expect(body["Operations"] == .array([.object(["op": .string("replace"),
                                                       "value": .object(["active": .bool(false)])])]))
        #expect(body["schemas"] == .array([.string("urn:ietf:params:scim:api:messages:2.0:PatchOp")]))
    }

    @Test
    func `uncertain mutations cannot be submitted twice`() async throws {
        let client = try client()
        NativeRequestCapture.status.withLock { $0 = 503 }
        let draft = try NativeFeatureFormModel(operationID: "api_create_interview_template")
        draft.body?.children.first { $0.name == "name" }?.text = "Synthetic Template"
        #expect(await !draft.submit(client: client, scimToken: nil))
        #expect(draft.uncertain)
        #expect(await !draft.submit(client: client, scimToken: nil))
        #expect(NativeRequestCapture.requests.withLock { $0.count } == 1)
    }

    @Test
    func `cursor audit continuation sends only its opaque cursor`() throws {
        let next = try NativeBusinessCollection.continuation(kind: .auditCursor, payload: [
            "has_more": .bool(true), "next_cursor": .string("opaque=+/cursor")
        ], query: [URLQueryItem(name: "user", value: "1")], count: 100)
        #expect(next == [URLQueryItem(name: "cursor", value: "opaque=+/cursor")])
    }

    @Test
    func `SCIM pagination advances by actual page size and stops at total`() throws {
        let first = try NativeBusinessCollection.continuation(kind: .provisioningUsers,
                                                              payload: ["totalResults": .int(3)], query: [URLQueryItem(
                                                                  name: "limit",
                                                                  value: "2"
                                                              )], count: 2)
        #expect(first?.contains(URLQueryItem(name: "offset", value: "2")) == true)
        #expect(try NativeBusinessCollection.continuation(
            kind: .provisioningUsers,
            payload: ["totalResults": .int(3)],
            query: first ?? [],
            count: 1
        ) == nil)
    }

    @Test(arguments: [
        ["api_create_test", "duration", "0"],
        ["api_invite_candidate", "invite_valid_to", "2098-01-01T10:00:00Z"],
        ["api_create_interview", "from", "2000-01-01T09:00:00Z"],
        ["api_create_team", "name", String(repeating: "x", count: 256)],
        ["api_create_user", "firstname", " "],
        ["api_create_question", "recommended_duration", "-1"]
    ])
    func `invalid native drafts never reach the service`(_ example: [String]) async throws {
        let client = try client()
        let draft = try NativeFeatureFormModel(operationID: example[0])
        draft.parameters.forEach(fill)
        let body = try #require(draft.body)
        fill(body)
        let field = try #require(body.children.first { $0.name == example[1] })
        field.text = example[2]
        #expect(await !(draft.submit(client: client, scimToken: nil)))
        #expect(draft.error != nil)
        #expect(NativeRequestCapture.requests.withLock { $0.isEmpty })
    }

    private func fill(_ field: NativeFormField) {
        field.included = true
        if ["from", "starttime", "invite_valid_from"].contains(field.name) {
            field.text = "2099-01-01T09:00:00Z"; return
        }
        if ["to", "endtime", "invite_valid_to"].contains(field.name) {
            field.text = "2099-01-01T10:00:00Z"; return
        }
        if let choice = field.choices.first {
            field.text = choice.text; return
        }
        switch field.kind {
        case "object": field.children.forEach(fill)
        case "array": field.addEntry(); field.entries.forEach(fill)
        case "integer", "number": field.text = "1"
        case "boolean": field.boolean = false
        default: field.text = "synthetic@example.test"
        }
    }

    private func readBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }

        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }

            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
}
