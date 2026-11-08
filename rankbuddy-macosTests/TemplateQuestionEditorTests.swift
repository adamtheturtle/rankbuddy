//
//  TemplateQuestionEditorTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Synchronization
import Testing

private final class TemplateMembershipURLProtocol: URLProtocol {
    private nonisolated struct State {
        var ids = [1, 2]
        var writes = 0
        var readOnly = false
        var denyReadback = false
        var wrongID = false
    }

    private static let state = Mutex(State())

    static func reset(readOnly: Bool = false, denyReadback: Bool = false, wrongID: Bool = false) {
        state.withLock { $0 = State(readOnly: readOnly, denyReadback: denyReadback, wrongID: wrongID) }
    }

    static var writes: Int {
        state.withLock { $0.writes }
    }

    static func allowReadback() {
        state.withLock { $0.denyReadback = false }
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }

        let result: (Int, [String: Any]) = Self.state.withLock { state in
            if url.path == "/x/api/v3/questions" {
                return (200, ["data": [["id": "3", "name": "Third", "type": "code"]], "next": NSNull()])
            }
            if request.httpMethod == "GET", state.denyReadback, state.writes > 0 {
                return (403, ["errors": ["Read denied"]])
            }
            if request.httpMethod == "PUT" {
                var data = request.httpBody ?? Data()
                if let stream = request.httpBodyStream {
                    stream.open()
                    defer { stream.close() }
                    var bytes = [UInt8](repeating: 0, count: 1024)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&bytes, maxLength: bytes.count)
                        if count <= 0 {
                            break
                        }
                        data.append(contentsOf: bytes.prefix(count))
                    }
                }
                let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                guard let ids = body?["question_ids"] as? [Int] else { return (400, [:]) }

                state.writes += 1
                state.ids += ids.filter { !state.ids.contains($0) }
            } else if request.httpMethod == "DELETE" {
                let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .first(where: { $0.name == "question_id" })?.value.flatMap(Int.init)
                state.writes += 1
                state.ids.removeAll { $0 == id }
            }
            return (200, ["id": state.wrongID ? "99" : "1", "name": "Template",
                          "questions": state.ids, "editor_access": !state.readOnly])
        }
        guard let response = HTTPURLResponse(
            url: url, statusCode: result.0, httpVersion: "HTTP/1.1", headerFields: nil
        ),
            let body = try? JSONSerialization.data(withJSONObject: result.1) else { return }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
@MainActor
struct TemplateQuestionEditorTests {
    private func model() -> TemplateQuestionEditorModel {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TemplateMembershipURLProtocol.self]
        let client = HackerRankClient(account: Account(label: "Synthetic", token: "synthetic-editor"),
                                      session: URLSession(configuration: configuration))
        return TemplateQuestionEditorModel(
            record: TemplateRecord(interview: InterviewTemplate(id: 1, name: "Template", editorAccess: true)),
            client: client
        )
    }

    @Test func `adds and removes questions through the SDK with readback`() async {
        TemplateMembershipURLProtocol.reset()
        let editor = model()
        #expect(await editor.refresh())
        await editor.loadMore()
        #expect(editor.candidates.map(\.id) == ["3"])
        await editor.add(Question(id: "3", type: "code", name: "Third"))
        #expect(editor.record.questionIDs == ["1", "2", "3"])
        #expect(editor.candidates.isEmpty)
        await editor.remove("2")
        #expect(editor.record.questionIDs == ["1", "3"])
        #expect(TemplateMembershipURLProtocol.writes == 2)
    }

    @Test func `read-only templates never issue a write`() async {
        TemplateMembershipURLProtocol.reset(readOnly: true)
        let editor = model()
        #expect(await editor.refresh())
        await editor.add(Question(id: "3", type: "code", name: "Third"))
        await editor.remove("1")
        #expect(!editor.canEdit)
        #expect(TemplateMembershipURLProtocol.writes == 0)
    }

    @Test func `a failed readback blocks further writes until refresh`() async {
        TemplateMembershipURLProtocol.reset(denyReadback: true)
        let editor = model()
        #expect(await editor.refresh())
        await editor.add(Question(id: "3", type: "code", name: "Third"))
        #expect(editor.needsRefresh)
        #expect(editor.errorMessage?.contains("saved") == true)
        await editor.remove("1")
        #expect(TemplateMembershipURLProtocol.writes == 1)
        TemplateMembershipURLProtocol.allowReadback()
        #expect(await editor.refresh())
        #expect(editor.record.questionIDs == ["1", "2", "3"])
        #expect(editor.canEdit)
    }

    @Test func `a mismatched template response never enables writes`() async {
        TemplateMembershipURLProtocol.reset(wrongID: true)
        let editor = model()
        #expect(await !editor.refresh())
        await editor.add(Question(id: "3", type: "code", name: "Third"))
        #expect(!editor.canEdit)
        #expect(TemplateMembershipURLProtocol.writes == 0)
    }
}
