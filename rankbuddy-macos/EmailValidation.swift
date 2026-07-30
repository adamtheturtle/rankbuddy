//
//  EmailValidation.swift
//  rankbuddy-macos
//

import Foundation

/// Lightweight, client-side email validation used to gate the invite-candidate action (#12).
///
/// Deliberately conservative: it only catches obvious typos before a request is sent so the
/// user gets immediate feedback. The HackerRank API is the real authority on whether an
/// address is acceptable — this never tries to fully implement RFC 5322.
enum EmailValidation {
    private static let localCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!#$%&'*+-/=?^_`{|}~"
    )
    private static let domainCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"
    )

    /// Whether `raw` looks like a plausible email: after trimming, exactly one `@`, a
    /// conservatively valid local part, and a dotted DNS-style domain.
    static func isLikelyValid(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }

        let local = parts[0]
        let domain = parts[1]
        guard
            !local.isEmpty,
            local.unicodeScalars.allSatisfy(localCharacters.contains),
            !local.hasPrefix("."),
            !local.hasSuffix("."),
            !local.contains(".."),
            domain.unicodeScalars.allSatisfy(domainCharacters.contains)
        else {
            return false
        }

        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && labels.allSatisfy {
            !$0.isEmpty && !$0.hasPrefix("-") && !$0.hasSuffix("-")
        }
    }
}
