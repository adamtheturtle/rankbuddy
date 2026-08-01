//
//  HackerRankLinkTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the URL/ID parsing behind "Open by URL" (#42) and the "Open in RankBuddy"
/// Service (#46, #32). `parse` finds a known collection segment and takes the segment after
/// it; anything without one (a bare id) returns nil so the caller can fall back to a picker.
@MainActor
struct HackerRankLinkTests {
    @Test(arguments: [
        ("https://www.hackerrank.com/x/tests/abc123/edit", FavoriteCollection.tests, "abc123"),
        ("https://www.hackerrank.com/x/questions/q-42", .questions, "q-42"),
        ("https://www.hackerrank.com/x/interviews/iv99", .interviews, "iv99"),
        // The path-relative case (no scheme/host): still split on `/`.
        ("tests/plain-id", .tests, "plain-id"),
        // Surrounding whitespace is trimmed before parsing.
        ("  https://hackerrank.com/x/tests/spaced  ", .tests, "spaced"),
        // A trailing slash after the id is tolerated (the empty segment is dropped).
        ("https://hackerrank.com/x/TESTS/t1/", .tests, "t1"),
        // The collection segment is matched case-insensitively.
        ("https://hackerrank.com/x/Tests/CaseId", .tests, "CaseId")
    ])
    func `a URL with a known collection segment resolves`(
        _ input: String, _ collection: FavoriteCollection, _ id: String
    ) {
        let parsed = HackerRankLink.parse(input)
        #expect(parsed?.collection == collection)
        #expect(parsed?.id == id)
    }

    /// The first known collection segment wins when more than one is present.
    @Test func `the first known collection segment wins`() {
        let parsed = HackerRankLink.parse("https://hackerrank.com/x/tests/t1/questions/q2")
        #expect(parsed?.collection == .tests)
        #expect(parsed?.id == "t1")
    }

    @Test(arguments: [
        // A bare id has no collection segment.
        "abc123",
        "",
        "   ",
        // A known segment with nothing after it can't yield an id.
        "https://hackerrank.com/x/tests/",
        "https://hackerrank.com/x/tests",
        // An unknown collection segment is ignored.
        "https://hackerrank.com/x/foo/bar"
    ])
    func `input without a usable collection segment returns nil`(_ input: String) {
        #expect(HackerRankLink.parse(input) == nil)
    }

    @Test func `opaque IDs are bounded and reject unsafe characters`() {
        #expect(HackerRankLink.isValidOpaqueID("test_1:revision-2.0"))
        #expect(!HackerRankLink.isValidOpaqueID("line\nbreak"))
        #expect(!HackerRankLink.isValidOpaqueID("contains/slash"))
        #expect(!HackerRankLink.isValidOpaqueID(String(repeating: "x", count: 256)))
        #expect(HackerRankLink.parse("https://hackerrank.com/x/tests/line%0Abreak") == nil)
    }

    @Test(arguments: [
        "https://evil.example/tests/some-id",
        "https://hackerrank.com.evil.example/tests/some-id",
        "ftp://hackerrank.com/tests/some-id",
        "https://user:secret@hackerrank.com/tests/some-id",
        "https://hackerrank.com\\@evil.example/tests/some-id"
    ])
    func `hosted URLs require a trusted HackerRank origin`(_ input: String) {
        #expect(HackerRankLink.parse(input) == nil)
    }

    @Test func `a configured enterprise host can be allowed explicitly`() {
        let parsed = HackerRankLink.parse(
            "https://hiring.example.org/x/tests/t1",
            allowedHosts: ["hiring.example.org"]
        )
        #expect(parsed?.collection == .tests)
        #expect(parsed?.id == "t1")
    }

    @Test func `a configured internal enterprise host remains supported`() {
        let parsed = HackerRankLink.parse(
            "http://hiring.acme.internal:8080/x/tests/t1",
            allowedHosts: ["hiring.acme.internal"]
        )
        #expect(parsed?.collection == .tests)
        #expect(parsed?.id == "t1")
    }

    @Test func `merged Open by URL requires an explicit account`() {
        let hiddenCurrent = UUID()
        let selected = UUID()

        #expect(OpenLinkAccountSelection.resolve(
            isMerged: true,
            selected: nil,
            current: hiddenCurrent
        ) == nil)
        #expect(OpenLinkAccountSelection.resolve(
            isMerged: true,
            selected: selected,
            current: hiddenCurrent
        ) == selected)
        #expect(OpenLinkAccountSelection.resolve(
            isMerged: false,
            selected: selected,
            current: hiddenCurrent
        ) == hiddenCurrent)
    }
}
