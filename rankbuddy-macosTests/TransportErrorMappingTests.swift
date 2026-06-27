//
//  TransportErrorMappingTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the transport error layer (#3, #32): `HackerRankError`'s user-facing
/// messages and `HackerRankErrorMapping`'s transient/permanent classification, which
/// decides what `PaginatedRESTClient` retries.
struct TransportErrorMappingTests {
    private let mapping = HackerRankErrorMapping()

    // MARK: - Error descriptions

    @Test func `missing api key has a configuration message`() {
        #expect(HackerRankError.missingAPIKey.errorDescription?.contains("token") == true)
    }

    @Test func `auth statuses explain that the token was rejected`() {
        for status in [401, 403] {
            let description = HackerRankError.http(status: status, body: "").errorDescription
            #expect(description?.contains("token was rejected") == true)
        }
    }

    @Test func `the rate-limited status mentions rate limiting`() {
        let description = HackerRankError.http(status: 429, body: "").errorDescription
        #expect(description?.lowercased().contains("rate-limiting") == true)
    }

    @Test func `the not-found status reports a missing resource`() {
        let description = HackerRankError.http(status: 404, body: "").errorDescription
        #expect(description?.contains("not found") == true)
    }

    @Test func `an unexpected status includes the code`() {
        let description = HackerRankError.http(status: 503, body: "").errorDescription
        #expect(description?.contains("503") == true)
    }

    // MARK: - Mapping factory

    @Test func `the mapping builds the matching error cases`() throws {
        if case .missingAPIKey = try #require(mapping.missingAPIKey() as? HackerRankError) {} else {
            Issue.record("expected .missingAPIKey")
        }

        let httpError = try #require(mapping.http(status: 500, body: "boom") as? HackerRankError)
        guard case let .http(status, body) = httpError else {
            Issue.record("expected .http"); return
        }

        #expect(status == 500)
        #expect(body == "boom")

        let decodeError = try #require(mapping.decode("bad json") as? HackerRankError)
        guard case let .decoding(detail) = decodeError else {
            Issue.record("expected .decoding"); return
        }

        #expect(detail == "bad json")
    }

    // MARK: - Transience classification

    @Test func `rate-limited and server-error statuses are transient`() {
        #expect(mapping.isTransient(HackerRankError.http(status: 429, body: "")))
        #expect(mapping.isTransient(HackerRankError.http(status: 500, body: "")))
        #expect(mapping.isTransient(HackerRankError.http(status: 503, body: "")))
    }

    @Test func `auth and not-found statuses are permanent`() {
        #expect(!mapping.isTransient(HackerRankError.http(status: 401, body: "")))
        #expect(!mapping.isTransient(HackerRankError.http(status: 403, body: "")))
        #expect(!mapping.isTransient(HackerRankError.http(status: 404, body: "")))
        #expect(!mapping.isTransient(HackerRankError.http(status: 400, body: "")))
    }

    @Test func `recoverable network errors are transient`() {
        let codes: [URLError.Code] = [
            .timedOut, .networkConnectionLost, .cannotConnectToHost,
            .notConnectedToInternet, .dnsLookupFailed
        ]
        for code in codes {
            #expect(mapping.isTransient(HackerRankError.network(URLError(code))))
        }
    }

    @Test func `a non-recoverable network error is permanent`() {
        #expect(!mapping.isTransient(HackerRankError.network(URLError(.unsupportedURL))))
    }

    @Test func `missing key and decoding failures are never retried`() {
        #expect(!mapping.isTransient(HackerRankError.missingAPIKey))
        #expect(!mapping.isTransient(HackerRankError.decoding("nope")))
    }

    @Test func `a foreign error type is not transient`() {
        struct Other: Error {}
        #expect(!mapping.isTransient(Other()))
    }
}
