import Foundation

/// Lightweight, client-side email validation used to gate the invite-candidate action (#12).
///
/// Deliberately conservative: it only catches obvious typos before a request is sent so the
/// user gets immediate feedback. The HackerRank API is the real authority on whether an
/// address is acceptable — this never tries to fully implement RFC 5322.
enum EmailValidation {
    /// Whether `raw` looks like a plausible email: after trimming, exactly one `@`, a
    /// non-empty local part, and a domain that contains a dot but neither starts nor ends
    /// with one (so `a@b`, `a@b.`, and `a@.b` are rejected, while `a@b.com` passes).
    static func isLikelyValid(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }

        let local = parts[0]
        let domain = parts[1]
        return !local.isEmpty && domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }
}
