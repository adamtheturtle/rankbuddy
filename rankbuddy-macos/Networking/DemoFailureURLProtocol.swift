//
//  DemoFailureURLProtocol.swift
//  rankbuddy-macos
//

import Foundation

/// Deterministic failure modes for UI, screenshot, and integration work (#10).
///
/// Launch with `RANKBUDDY_DEMO_SCENARIO` set to one of the raw values, then select/add
/// the normal `demo` account. Only that account is affected; live accounts still use
/// their ordinary authenticated sessions.
nonisolated enum DemoFailureScenario: String, CaseIterable {
    case empty
    case validation
    case throttled
    case malformed
    case serverError = "server-error"

    static let environmentKey = "RANKBUDDY_DEMO_SCENARIO"

    init?(environment: [String: String]) {
        guard let value = environment[Self.environmentKey]?.lowercased() else { return nil }

        self.init(rawValue: value)
    }

    var response: (status: Int, body: Data) {
        switch self {
        case .empty:
            (200, Data(#"{"data":[],"next":null}"#.utf8))
        case .validation:
            (422, Data(#"{"message":"Demo validation failed"}"#.utf8))
        case .throttled:
            (429, Data(#"{"message":"Demo rate limit reached"}"#.utf8))
        case .malformed:
            (200, Data("this is not JSON".utf8))
        case .serverError:
            (503, Data(#"{"message":"Demo service unavailable"}"#.utf8))
        }
    }

    func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        let protocolClass: URLProtocol.Type = switch self {
        case .empty: EmptyDemoURLProtocol.self
        case .validation: ValidationDemoURLProtocol.self
        case .throttled: ThrottledDemoURLProtocol.self
        case .malformed: MalformedDemoURLProtocol.self
        case .serverError: ServerErrorDemoURLProtocol.self
        }
        configuration.protocolClasses = [protocolClass]
        return URLSession(configuration: configuration)
    }
}

/// An in-process transport that never reaches the network.
private nonisolated class DemoFailureURLProtocol: URLProtocol, @unchecked Sendable {
    class var scenario: DemoFailureScenario {
        preconditionFailure("A concrete demo protocol must provide its scenario.")
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let result = Self.scenario.response
        let headers = result.status == 429 ? ["Retry-After": "0"] : [:]
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: result.status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private nonisolated class EmptyDemoURLProtocol: DemoFailureURLProtocol, @unchecked Sendable {
    override class var scenario: DemoFailureScenario {
        .empty
    }
}

private nonisolated class ValidationDemoURLProtocol: DemoFailureURLProtocol, @unchecked Sendable {
    override class var scenario: DemoFailureScenario {
        .validation
    }
}

private nonisolated class ThrottledDemoURLProtocol: DemoFailureURLProtocol, @unchecked Sendable {
    override class var scenario: DemoFailureScenario {
        .throttled
    }
}

private nonisolated class MalformedDemoURLProtocol: DemoFailureURLProtocol, @unchecked Sendable {
    override class var scenario: DemoFailureScenario {
        .malformed
    }
}

private nonisolated class ServerErrorDemoURLProtocol: DemoFailureURLProtocol, @unchecked Sendable {
    override class var scenario: DemoFailureScenario {
        .serverError
    }
}
