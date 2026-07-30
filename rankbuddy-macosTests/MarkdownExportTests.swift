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

        #expect(markdown.contains(#"# \# \[Report\]\(https://example.com\)"#))
        #expect(markdown.contains(#"_\_unsafe\__"#))
        #expect(markdown.contains(#"## \* Section"#))
        #expect(markdown.contains(#"- **La\*\*bel:** \`code\` \- \[link\]\(x\)"#))
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
}
