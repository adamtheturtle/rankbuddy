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
/// markup, decode entities, and degrade gracefully. `@MainActor` because AppKit's HTML
/// importer is main-thread-only.
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
}
