@testable import rankbuddy_macos
import Testing

/// Verifies the command palette's deterministic fuzzy ranking (#18) — and, incidentally,
/// that the test target can `@testable import` the app module.
struct FuzzyMatchTests {
    @Test func `non subsequence does not match`() {
        #expect(FuzzyMatch.score(query: "zzz", in: "Tests") == nil)
    }

    @Test func `subsequence matches`() {
        #expect(FuzzyMatch.score(query: "ts", in: "Tests") != nil)
    }

    @Test func `empty query scores zero`() {
        #expect(FuzzyMatch.score(query: "", in: "Anything") == 0)
    }

    @Test func `word start outranks mid word`() throws {
        let wordStart = try #require(FuzzyMatch.score(query: "q", in: "Questions"))
        let midWord = try #require(FuzzyMatch.score(query: "t", in: "Questions"))
        #expect(wordStart > midWord)
    }
}
