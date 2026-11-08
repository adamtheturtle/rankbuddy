//
//  FormattingTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the pure display helpers (#32): `DisplayFormat`'s date/list formatting and
/// the `TestCandidate.integrityBadge` derivation that drives the plagiarism/integrity pill.
@MainActor
struct FormattingTests {
    @Test func `tag chips deduplicate values while preserving API order`() {
        #expect(uniqueTags(["swift", "api", "swift", "macOS"]) == ["swift", "api", "macOS"])
        #expect(uniqueTags(nil).isEmpty)
    }

    // MARK: - DisplayFormat.languages

    @Test func `language codes normalise to friendly names`() {
        #expect(DisplayFormat.languageName("cpp") == "C++")
        #expect(DisplayFormat.languageName("python") == "Python")
        #expect(DisplayFormat.languageName("CSHARP") == "C#")
        // An unknown code is title-cased rather than dropped.
        #expect(DisplayFormat.languageName("brainfuck") == "Brainfuck")
    }

    @Test(arguments: [
        ["cpp23", "C++23"], ["cpp26", "C++26"], ["cplusplus23", "C++23"],
        ["JAVA_21", "Java 21"], ["java25", "Java 25"], ["csharp12", "C# 12"],
        ["javascript", "JavaScript"], ["objectivec", "Objective-C"]
    ])
    func `versioned language labels preserve names and versions`(_ example: [String]) {
        #expect(DisplayFormat.languageName(example[0]) == example[1])
    }

    @Test func `languages joins normalised names and omits empties`() {
        #expect(DisplayFormat.languages(nil) == nil)
        #expect(DisplayFormat.languages([]) == nil)
        #expect(DisplayFormat.languages(["python", "go"]) == "Python and Go")
    }

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

    @Test func `parsed dates compare chronological instants across representations`() throws {
        let earlier = try #require(DisplayFormat.parseDate("2026-05-01T10:30:00.500+02:00"))
        let later = try #require(DisplayFormat.parseDate("2026-05-01T09:00:01Z"))

        #expect(later > earlier)
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

    // MARK: - DisplayFormat.boolean

    @Test func `boolean distinguishes false from unavailable`() {
        #expect(DisplayFormat.boolean(true) == "Yes")
        #expect(DisplayFormat.boolean(false) == "No")
        #expect(DisplayFormat.boolean(nil) == "Unavailable")
        #expect(DisplayFormat.boolean(true, trueLabel: "Enabled", falseLabel: "Disabled") == "Enabled")
        #expect(DisplayFormat.boolean(false, trueLabel: "Enabled", falseLabel: "Disabled") == "Disabled")
    }

    // MARK: - DisplayFormat.enumLabel

    @Test func `backend enum labels replace separators and normalize spacing`() {
        let missing: String? = nil
        #expect(DisplayFormat.enumLabel("in_progress") == "In Progress")
        #expect(DisplayFormat.enumLabel("company-admin") == "Company Admin")
        #expect(DisplayFormat.enumLabel("  report   ready ") == "Report Ready")
        #expect(DisplayFormat.enumLabel(missing) == nil)
    }

    // MARK: - DisplayFormat.duration

    @Test func `duration formats the elapsed time between two timestamps`() {
        let elapsed = DisplayFormat.duration(
            fromISO: "2026-05-02T10:00:00Z",
            toISO: "2026-05-02T11:15:00Z"
        )
        // Locale-dependent rendering, so assert the components rather than an exact string.
        #expect(elapsed?.contains("1") == true)
        #expect(elapsed?.contains("15") == true)
    }

    @Test func `duration is nil for missing, unparseable, or non-positive spans`() {
        #expect(DisplayFormat.duration(fromISO: nil, toISO: "2026-05-02T11:15:00Z") == nil)
        #expect(DisplayFormat.duration(fromISO: "2026-05-02T10:00:00Z", toISO: nil) == nil)
        // End not after start.
        #expect(DisplayFormat.duration(fromISO: "2026-05-02T11:15:00Z", toISO: "2026-05-02T10:00:00Z") == nil)
    }

    // MARK: - DisplayFormat.interval

    @Test func `interval formats a positive number of seconds`() {
        let formatted = DisplayFormat.interval(95)
        #expect(formatted?.contains("1") == true)
        #expect(formatted?.contains("35") == true)
    }

    @Test func `interval is nil for nil or non-positive seconds`() {
        #expect(DisplayFormat.interval(nil) == nil)
        #expect(DisplayFormat.interval(0) == nil)
        #expect(DisplayFormat.interval(-10) == nil)
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
