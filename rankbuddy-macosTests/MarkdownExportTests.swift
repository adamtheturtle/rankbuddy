//
//  MarkdownExportTests.swift
//  rankbuddy-macosTests
//

import Foundation
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
}
