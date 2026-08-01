//
//  MarkdownExportTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for Markdown export (#50): section/field rendering, HTML stripping, and the
/// candidate document.
@MainActor
struct MarkdownExportTests {
    @Test func `a section lists only fields with values`() {
        let markdown = MarkdownExport.section("Candidate", [("Name", "Ada"), ("Score", nil), ("Email", "a@b.c")])
        #expect(markdown == "## Candidate\n- **Name:** Ada\n- **Email:** a@b.c")
    }

    @Test func `an all-empty section renders nothing`() {
        #expect(MarkdownExport.section("X", [("A", nil), ("B", nil)]).isEmpty)
        #expect(MarkdownExport.textSection("Notes", nil).isEmpty)
        #expect(MarkdownExport.textSection("Notes", "").isEmpty)
    }

    @Test func `HTML is reduced to plain text`() {
        let text = MarkdownExport.plainText(fromHTML: "<p>Solve <b>two&nbsp;sum</b> &amp; return.</p>")
        #expect(text == "Solve two sum & return.")
    }

    @Test func `HTML entities are decoded exactly once`() {
        #expect(MarkdownExport.plainText(fromHTML: "&amp;lt;tag&amp;gt;") == "&lt;tag&gt;")
    }

    @Test func `decimal and hexadecimal HTML entities are decoded`() {
        #expect(MarkdownExport.plainText(fromHTML: "&#169; &#60; &#x1F600;") == "© < 😀")
    }

    @Test func `HTML blocks and breaks retain text boundaries`() {
        let html = "<p>Hello</p><p>World<br>Again</p>"
        #expect(MarkdownExport.plainText(fromHTML: html) == "Hello\nWorld\nAgain")
    }

    @Test func `inline field values are single-line and bounded`() {
        let oversized = String(repeating: "x", count: MarkdownExport.Limits.inlineCharacters + 1)
        let markdown = MarkdownExport.section("Candidate\nForged", [("Name", "Ada\n- forged"), ("Bio", oversized)])

        #expect(markdown.hasPrefix("## Candidate Forged\n"))
        #expect(markdown.contains("- **Name:** Ada \\- forged"))
        #expect(markdown.contains(String(repeating: "x", count: MarkdownExport.Limits.inlineCharacters) + "..."))
    }

    @Test func `untrusted text cannot inject Markdown structure`() {
        let markdown = MarkdownExport.document(
            title: "# [Report](https://example.com)",
            subtitle: "_unsafe_",
            sections: [
                MarkdownExport.section("* Section", [("La**bel", "`code` - [link](x)")]),
                MarkdownExport.textSection("Notes", "# Heading\n- item\n<script>alert(1)</script>")
            ]
        )

        #expect(markdown.contains("# \\# \\[Report\\]\\(https://example.com\\)"))
        #expect(markdown.contains("_\\_unsafe\\__"))
        #expect(markdown.contains("## \\* Section"))
        #expect(markdown.contains("- **La\\*\\*bel:** \\`code\\` \\- \\[link\\]\\(x\\)"))
        #expect(markdown.contains("\\# Heading\n\\- item\n\\<script\\>alert\\(1\\)\\</script\\>"))
    }

    @Test func `oversized prose and HTML are truncated before export`() {
        let prose = String(repeating: "p", count: MarkdownExport.Limits.proseCharacters + 1)
        let markdown = MarkdownExport.textSection("Notes", prose)
        let html = MarkdownExport.plainText(fromHTML: "<p>\(prose)</p>")

        #expect(markdown.contains("_Content truncated for export._"))
        #expect(!markdown.contains(prose))
        #expect(html.contains("Content truncated for export."))
        #expect(!html.contains(prose))
    }

    @Test func `ignored HTML is removed before visible text is bounded`() {
        let stylesheet = String(repeating: "x", count: MarkdownExport.Limits.proseCharacters + 1)
        let html = MarkdownExport.plainText(fromHTML: "<style>\(stylesheet)</style><p>Useful prose</p>")

        #expect(html == "Useful prose")
    }

    @Test func `suggested export filenames are path-safe`() {
        #expect(FileExport.sanitizedSuggestedName("Team/Question: Report.md") == "Team-Question- Report.md")
        #expect(FileExport.sanitizedSuggestedName("...") == "Export")
        #expect(FileExport.sanitizedSuggestedName("  \n  ") == "Export")
    }

    @Test func `the candidate document has a title and the candidate section`() throws {
        let json = #"""
        {"id":"c1","email":"ada@example.com","full_name":"Ada Lovelace","score":92.0,
         "status":7,"plagiarism_status":false,"feedback":"Strong."}
        """#
        let candidate = try JSONDecoder().decode(TestCandidate.self, from: Data(json.utf8))
        let markdown = MarkdownExport.candidate(candidate)
        #expect(markdown.hasPrefix("# Ada Lovelace"))
        #expect(markdown.contains("_HackerRank Candidate Report_"))
        #expect(markdown.contains("- **Email:** ada@example.com"))
        #expect(markdown.contains("## Feedback\nStrong."))
    }

    @Test func `interview export uses edited title and notes overlays`() throws {
        let interview = try JSONDecoder().decode(
            Interview.self,
            from: Data(#"{"id":"i1","title":"Old","notes":"Old notes","status":"scheduled"}"#.utf8)
        )
        let markdown = MarkdownExport.interview(interview, title: "New", notes: "New notes")
        #expect(markdown.hasPrefix("# New"))
        #expect(markdown.contains("## Notes\nNew notes"))
        #expect(!markdown.contains("Old notes"))
    }

    @Test func `interview export includes loaded detail and transcript`() throws {
        let interview = try JSONDecoder().decode(
            Interview.self,
            from: Data(#"{"id":"i1","title":"Pairing","status":"scheduled"}"#.utf8)
        )
        let detail = try JSONDecoder().decode(
            InterviewDetail.self,
            from: Data(
                #"{"from":"2026-07-30T09:00:00Z","result_url":"https://hr.test/result","candidate":"Ada"}"#.utf8
            )
        )
        let transcript = try JSONDecoder().decode(
            InterviewTranscript.self,
            from: Data(#"{"messages":[{"author":"Ian","text":"Hello"},{"candidate":true,"text":"Hi"}]}"#.utf8)
        )
        let markdown = MarkdownExport.interview(InterviewReportData(
            interview: interview,
            detail: detail,
            transcript: transcript
        ))

        #expect(markdown.contains("- **Result URL:** https://hr.test/result"))
        #expect(markdown.contains("- **Candidate:** Ada"))
        #expect(markdown.contains("## Transcript\nIan: Hello\n\nCandidate: Hi"))
    }

    @Test func `export includes loaded detail and inviters without an unrevealed password`() throws {
        let test = try JSONDecoder().decode(
            Test.self,
            from: Data(#"{"id":"t1","name":"Swift","questions":["q1"],"library":"Backend"}"#.utf8)
        )
        let detail = try JSONDecoder().decode(
            TestDetail.self,
            from: Data(
                #"{"short_login_url":"https://hr.test/s","master_password":"secret","mcq_correct_score":4}"#.utf8
            )
        )
        let inviter = TestInviter(id: "u1", email: "ada@example.com", firstName: "Ada", role: "Owner")

        let hidden = MarkdownExport.test(TestReportData(test: test, detail: detail, inviters: [inviter]))
        let revealed = MarkdownExport.test(TestReportData(
            test: test,
            detail: detail,
            inviters: [inviter],
            includeAccessPassword: true
        ))

        #expect(hidden.contains("- **Questions:** 1"))
        #expect(hidden.contains("- **MCQ correct score:** 4"))
        #expect(hidden.contains("- **Short login URL:** https://hr.test/s"))
        #expect(hidden.contains("- **Ada:** ada@example.com — Owner"))
        #expect(!hidden.contains("secret"))
        #expect(revealed.contains("- **Access password:** secret"))
    }

    @Test func `question export includes rich detail while respecting answer reveal`() throws {
        let question = try JSONDecoder().decode(
            Question.self,
            from: Data(#"{"id":"q1","name":"SQL","type":"mcq","status":"active"}"#.utf8)
        )
        let detail = try JSONDecoder().decode(
            QuestionDetail.self,
            from: Data(
                #"{"options":["JOIN","SELECT"],"answer":"JOIN","internal_notes":"<p>Use joins.</p>"}"#.utf8
            )
        )

        let hidden = MarkdownExport.question(QuestionReportData(question: question, detail: detail))
        let revealed = MarkdownExport.question(QuestionReportData(
            question: question,
            detail: detail,
            includeCorrectAnswer: true
        ))

        #expect(hidden.contains("- **Option 1:** JOIN"))
        #expect(hidden.contains("## Internal notes\nUse joins."))
        #expect(!hidden.contains("correct"))
        #expect(revealed.contains("- **Option 1:** JOIN \\(correct\\)"))
        #expect(revealed.contains("## Correct answer\nJOIN"))
    }
}
