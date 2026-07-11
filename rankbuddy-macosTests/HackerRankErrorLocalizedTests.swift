//
//  HackerRankErrorLocalizedTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the app's user-facing `HackerRankError` copy (the retroactive `LocalizedError`
/// conformance). The write flows and the account-health banner read `errorDescription`, so these
/// messages are what a user actually sees when a call fails.
struct HackerRankErrorLocalizedTests {
    private func description(_ error: HackerRankError) -> String? {
        (error as LocalizedError).errorDescription
    }

    @Test func `a missing token explains no token is configured`() {
        #expect(description(.missingAPIKey) == "No HackerRank token is configured for this account.")
    }

    @Test func `unauthorized and forbidden both report a rejected token`() {
        let expected = "The token was rejected. Check that it is a valid HackerRank for Work personal access token."
        #expect(description(.http(401, "")) == expected)
        #expect(description(.http(403, "")) == expected)
    }

    @Test func `too many requests reports rate limiting`() {
        #expect(description(.http(429, "")) == "HackerRank is rate-limiting requests. Please try again shortly.")
    }

    @Test func `not found reports a missing resource`() {
        #expect(description(.http(404, "")) == "The requested HackerRank resource was not found.")
    }

    @Test func `an unmapped status falls back to the raw HTTP code`() {
        #expect(description(.http(500, "boom")) == "HackerRank returned an unexpected error (HTTP 500).")
    }

    @Test func `an errors array surfaces the server explanation`() {
        #expect(description(.http(400, #"{"errors": ["Email has already been taken"]}"#))
            == "HackerRank rejected the request (HTTP 400): Email has already been taken.")
    }

    @Test func `a message field surfaces the server explanation`() {
        #expect(description(.http(422, #"{"message": "Role is not valid."}"#))
            == "HackerRank rejected the request (HTTP 422): Role is not valid.")
    }

    @Test func `errors objects with message fields are surfaced`() {
        #expect(description(.http(400, #"{"errors": [{"message": "Email is invalid"}]}"#))
            == "HackerRank rejected the request (HTTP 400): Email is invalid.")
    }

    @Test func `field-keyed errors name the field`() {
        #expect(description(.http(400, #"{"errors": {"email": ["has already been taken"]}}"#))
            == "HackerRank rejected the request (HTTP 400): Email has already been taken.")
    }

    @Test func `a non-JSON body still falls back to the raw HTTP code`() {
        #expect(description(.http(400, "<html>Bad Request</html>"))
            == "HackerRank returned an unexpected error (HTTP 400).")
    }

    @Test func `a decode failure reports an unreadable response`() {
        #expect(description(.decode("bad json")) == "The response from HackerRank could not be read.")
    }

    @Test func `a transport failure surfaces the underlying reason`() {
        let message = description(.network(URLError(.notConnectedToInternet)))
        #expect(message?.hasPrefix("Could not reach HackerRank:") == true)
    }
}
