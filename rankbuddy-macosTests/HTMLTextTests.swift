//
//  HTMLTextTests.swift
//  rankbuddy-macosTests
//

import AppKit
import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the HTML rendering helper behind `HTMLText` (#35): HackerRank delivers
/// instructions / problem statements as HTML, so `AttributedString.fromHTML` must strip the
/// markup, decode entities, and degrade gracefully.
@MainActor
struct HTMLTextTests {
    private func plainText(_ html: String) -> String {
        String(AttributedString.fromHTML(html).characters)
    }

    @Test func `strips block and inline tags`() {
        let text = plainText("<p>Solve <b>all</b> questions within the <i>time limit</i>.</p>")
        #expect(text == "Solve all questions within the time limit.")
        #expect(!text.contains("<"))
        #expect(!text.contains(">"))
    }

    @Test func `decodes character entities`() {
        #expect(plainText("Inputs &amp; outputs &lt;3").contains("Inputs & outputs <3"))
    }

    @Test func `renders list items as separate lines`() {
        let text = plainText("<ul><li>First</li><li>Second</li></ul>")
        #expect(text.contains("First"))
        #expect(text.contains("Second"))
        #expect(!text.contains("<li>"))
    }

    @Test func `trims the importer's trailing newline`() {
        let text = plainText("<p>Only line</p>")
        #expect(text == "Only line")
        #expect(text.last != "\n")
    }

    @Test func `plain text without markup is preserved`() {
        #expect(plainText("Just some plain instructions.") == "Just some plain instructions.")
    }

    @Test func `an empty string renders empty`() {
        #expect(plainText("").isEmpty)
    }

    @Test func `explicit foreground and background colors are removed`() {
        let rendered = AttributedString.fromHTML(
            #"<span style="color: white; background-color: black">Adaptive</span>"#
        )
        let attributed = NSAttributedString(rendered)
        #expect(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
        #expect(attributed.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
    }

    @Test func `normalisation applies a body font to every range`() {
        let source = NSMutableAttributedString(string: "plain bold")
        source.addAttribute(
            .font,
            value: NSFont.boldSystemFont(ofSize: 30),
            range: NSRange(location: 6, length: 4)
        )

        let rendered = AttributedString.normalised(source)
        let plainFont = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let boldFont = rendered.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
        #expect(plainFont?.pointSize == NSFont.preferredFont(forTextStyle: .body).pointSize)
        #expect(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test func `remote resources are removed before HTML import`() {
        let html = """
        <style>@import "https://styles.example/theme.css";</style>
        <p style="background:url(https://track.example/pixel)">Safe text</p>
        <img src="https://images.example/pixel.png">
        <a href="https://links.example/">Link text</a>
        """
        let safe = AttributedString.resourceSafeHTML(html)
        #expect(!safe.contains("https://"))
        #expect(!safe.lowercased().contains("<img"))
        #expect(plainText(html).contains("Safe text"))
        #expect(plainText(html).contains("Link text"))
    }

    @Test func `ordered lists ignore comments and scripts`() {
        let comment = "before<!-- <ol><li>hidden</li></ol> -->after"
        let script = "<script>const example = '<ol><li>hidden</li></ol>';</script><p>shown</p>"
        #expect(HTMLFragmentSegment.segments(from: comment) == [.prose(comment)])
        #expect(HTMLFragmentSegment.segments(from: script) == [.prose(script)])
        #expect(HTMLFragmentSegment.segments(
            from: "<ol><li>shown</li><!-- <li>hidden</li> --></ol>"
        ) == [.orderedList(["shown"])])
    }
}
