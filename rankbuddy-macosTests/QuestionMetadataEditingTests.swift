//
//  QuestionMetadataEditingTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Synchronization
import Testing

private final nonisolated class QuestionMetadataURLProtocol: URLProtocol {
    struct State {
        var snapshot = #"""
        {"id":"q1","name":"Project","type":"fullstack","problem_statement":"Candidate instructions",
         "recommended_duration":45,"internal_notes":"Private notes","languages":["python3"],
         "tags":["rubric"],"options":["A","B"],"answer":"0","custom_system_prompt":"Remote prompt"}
        """#
        var status = 200
        var methods: [String] = []
        var writtenBody = Data()
        var writeURL: URL?
    }

    static let state = Mutex(State())

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }

        let body = readBody()
        let (status, responseBody) = Self.state.withLock { state in
            state.methods.append(request.httpMethod ?? "")
            if request.httpMethod == "PUT" {
                state.writtenBody = body
                state.writeURL = url
                return (200, "{}")
            }
            return (state.status, state.snapshot)
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else { return }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func readBody() -> Data {
        if let data = request.httpBody {
            return data
        }
        guard let stream = request.httpBodyStream else { return Data() }

        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 {
                break
            }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}

@Suite(.serialized)
@MainActor
struct QuestionMetadataEditingTests {
    private func client() -> HackerRankClient {
        QuestionMetadataURLProtocol.state.withLock { $0 = .init() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QuestionMetadataURLProtocol.self]
        return HackerRankClient(account: Account(label: "Synthetic", token: "synthetic-editor"),
                                session: URLSession(configuration: configuration))
    }

    @Test func `inline edits use the released SDK snapshot and canonical write route`() async throws {
        let client = client()
        _ = try await client.updateQuestionMetadata(questionID: "q1", changes: QuestionMetadataChanges(name: "Renamed"))
        let state = QuestionMetadataURLProtocol.state.withLock { $0 }
        let body = try JSONDecoder().decode(HackerRankJSONValue.self, from: state.writtenBody)
        #expect(state.methods == ["GET", "PUT"])
        #expect(state.writeURL?.absoluteString.hasSuffix("/q1/") == true)
        #expect(body == .object([
            "name": .string("Renamed"), "type": .string("fullstack"),
            "problem_statement": .string("Candidate instructions"), "recommended_duration": .int(45),
            "internal_notes": .string("Private notes"), "languages": .array([.string("python3")]),
            "tags": .array([.string("rubric")]), "options": .array([.string("A"), .string("B")]),
            "answer": .string("0")
        ]))
    }

    @Test func `prompt clearing empty lists and zero remain selected values`() async throws {
        let client = client()
        let changes = QuestionMetadataChanges(languages: [], recommendedDuration: 0, tags: [], customSystemPrompt: "")
        _ = try await client.updateQuestionMetadata(questionID: "q1", changes: changes)
        let body = try JSONDecoder().decode(HackerRankJSONValue.self,
                                            from: QuestionMetadataURLProtocol.state.withLock { $0.writtenBody })
        #expect(body.object["custom_system_prompt"] == .string(""))
        #expect(body.object["languages"] == .array([]))
        #expect(body.object["tags"] == .array([]))
        #expect(body.object["recommended_duration"] == .int(0))
        var overlay = QuestionEditOverlay()
        overlay.merge(changes)
        overlay.merge(QuestionMetadataChanges(name: "Renamed"))
        let displayed = overlay.applying(to: Question(id: "q1", type: "fullstack", name: "Project",
                                                      languages: ["python3"], recommendedDuration: 45,
                                                      tags: ["rubric"], customSystemPrompt: "Remote prompt"))
        #expect(displayed.customSystemPrompt?.isEmpty == true)
        #expect(displayed.languages?.isEmpty == true)
        #expect(displayed.tags?.isEmpty == true)
        #expect(displayed.recommendedDuration == 0)
    }

    @Test(arguments: [false, true])
    func `failed or incomplete snapshots prevent a metadata write`(denied: Bool) async {
        let client = client()
        QuestionMetadataURLProtocol.state.withLock {
            $0.status = denied ? 403 : 200
            $0.snapshot = #"{"id":"q1","name":"Project","type":"fullstack"}"#
        }
        await #expect(throws: (any Error).self) {
            try await client.updateQuestionMetadata(questionID: "q1", changes: QuestionMetadataChanges(name: "Renamed"))
        }
        #expect(QuestionMetadataURLProtocol.state.withLock { $0.methods } == ["GET"])
    }

    @Test func `unknown types remain browsable without enabling prompt editing`() {
        let question = Question(id: "future", type: "future_type", name: "Future")
        #expect(question.knownType == nil)
        #expect(!question.supportsCustomSystemPrompt)
        #expect(QuestionReportData(question: question).question.type == "future_type")
        let project = Question(id: "project", type: QuestionType.fullstack.rawValue, name: "Project")
        #expect(project.supportsCustomSystemPrompt)
    }
}
