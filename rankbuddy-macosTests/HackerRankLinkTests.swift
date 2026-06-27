@testable import rankbuddy_macos
import Testing

/// Coverage for Open-by-URL parsing (#42).
struct HackerRankLinkTests {
    @Test func `a tests URL parses to the test collection and id`() {
        let parsed = HackerRankLink.parse("https://www.hackerrank.com/x/tests/abc123/candidates")
        #expect(parsed?.collection == .tests)
        #expect(parsed?.id == "abc123")
    }

    @Test func `questions and interviews URLs are recognised`() {
        #expect(HackerRankLink.parse("https://www.hackerrank.com/x/questions/q9")?.collection == .questions)
        #expect(HackerRankLink.parse("https://www.hackerrank.com/x/interviews/i7")?.id == "i7")
    }

    @Test func `matching is case-insensitive and tolerates a trailing slash`() {
        #expect(HackerRankLink.parse("  https://host/x/TESTS/t1/  ")?.id == "t1")
    }

    @Test func `a bare id or unknown path yields nil so the caller picks a type`() {
        #expect(HackerRankLink.parse("abc123") == nil)
        #expect(HackerRankLink.parse("https://host/x/leaderboards/l1") == nil)
        #expect(HackerRankLink.parse("") == nil)
    }
}
