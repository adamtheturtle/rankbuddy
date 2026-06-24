import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the pure display helpers (#32): `DisplayFormat`'s date/list formatting and
/// the `TestCandidate.integrityBadge` derivation that drives the plagiarism/integrity pill.
struct FormattingTests {
    // MARK: - DisplayFormat.date

    @Test func `date returns nil for nil or empty input`() {
        #expect(DisplayFormat.date(nil) == nil)
        #expect(DisplayFormat.date("") == nil)
    }

    @Test func `date parses a plain internet timestamp`() {
        // A parseable timestamp is reformatted, so it differs from the raw string.
        let formatted = DisplayFormat.date("2026-05-01T09:00:00Z")
        #expect(formatted != nil)
        #expect(formatted != "2026-05-01T09:00:00Z")
    }

    @Test func `date parses a fractional-seconds timestamp`() {
        #expect(DisplayFormat.date("2026-05-01T09:00:00.500Z") != nil)
    }

    @Test func `date parses the live +0000 offset format`() {
        // Regression cover for the live API's `+0000` offset (see ModelDecodingTests).
        #expect(DisplayFormat.date("2026-06-22T04:10:51+0000") != nil)
    }

    @Test func `date falls back to the raw string when unparseable`() {
        #expect(DisplayFormat.date("not a date") == "not a date")
    }

    // MARK: - DisplayFormat.list

    @Test func `list returns nil for nil or empty arrays`() {
        #expect(DisplayFormat.list(nil) == nil)
        #expect(DisplayFormat.list([]) == nil)
    }

    @Test func `list renders a single value verbatim`() {
        #expect(DisplayFormat.list(["python"]) == "python")
    }

    @Test func `list joins multiple values with and`() {
        let formatted = DisplayFormat.list(["python", "go", "java"])
        #expect(formatted?.contains("python") == true)
        #expect(formatted?.contains("and") == true)
    }

    // MARK: - integrityBadge

    private func candidate(integrity: String?, plagiarism: Bool?) throws -> TestCandidate {
        let json = """
        {"id":"c1","email":"a@b.com",
         "integrity_status":\(integrity.map { "\"\($0)\"" } ?? "null"),
         "plagiarism_status":\(plagiarism.map(String.init) ?? "null")}
        """
        return try JSONDecoder().decode(TestCandidate.self, from: Data(json.utf8))
    }

    @Test func `a plagiarism flag wins over the integrity status`() throws {
        let badge = try candidate(integrity: "clean", plagiarism: true).integrityBadge
        #expect(badge?.text == "Plagiarism")
    }

    @Test func `a review integrity status yields a review badge`() throws {
        #expect(try candidate(integrity: "review", plagiarism: false).integrityBadge?.text == "Review")
        #expect(try candidate(integrity: "flagged", plagiarism: nil).integrityBadge?.text == "Review")
    }

    @Test func `a clean status yields a clean badge`() throws {
        #expect(try candidate(integrity: "Clean", plagiarism: false).integrityBadge?.text == "Clean")
    }

    @Test func `an unknown or absent status yields no badge`() throws {
        #expect(try candidate(integrity: nil, plagiarism: false).integrityBadge == nil)
        #expect(try candidate(integrity: "something-new", plagiarism: nil).integrityBadge == nil)
    }
}
