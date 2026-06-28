//
//  EmailValidationTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the client-side email check that gates the invite action (#12, #32). It's
/// intentionally lenient — these pin the obvious accept/reject cases, not RFC conformance.
@MainActor
struct EmailValidationTests {
    @Test(arguments: [
        "ada@example.com",
        "ada.lovelace@sub.example.co.uk",
        "  trimmed@example.com  ",
        "a@b.c"
    ])
    func `plausible addresses are accepted`(_ email: String) {
        #expect(EmailValidation.isLikelyValid(email))
    }

    @Test(arguments: [
        "",
        "   ",
        "no-at-sign.com",
        "@example.com",
        "ada@",
        "ada@nodot",
        "ada@trailing.",
        "ada@.leading",
        "two@@example.com",
        "ada@example@com"
    ])
    func `malformed addresses are rejected`(_ email: String) {
        #expect(!EmailValidation.isLikelyValid(email))
    }
}
