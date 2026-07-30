//
//  HTMLCodeBlocksTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

struct HTMLCodeBlocksTests {
    @Test func `plain html with no code is a single prose segment`() {
        let html = "<p>Hello <b>world</b></p>"
        #expect(HTMLCodeBlocks.segments(html) == [.prose(html)])
    }

    @Test func `a code block is split out with prose around it`() {
        let html = "<p>Before</p><pre><code class=\"language-python\">x = 1</code></pre><p>After</p>"
        let segments = HTMLCodeBlocks.segments(html)
        #expect(segments == [
            .prose("<p>Before</p>"),
            .code(languageHint: "python", code: "x = 1"),
            .prose("<p>After</p>")
        ])
    }

    @Test func `entities inside code are decoded`() {
        let html = "<pre><code>if (a &lt; b &amp;&amp; b &gt; 0) {}</code></pre>"
        let segments = HTMLCodeBlocks.segments(html)
        #expect(segments == [.code(languageHint: nil, code: "if (a < b && b > 0) {}")])
    }

    @Test func `amp is decoded last so escaped entities survive`() {
        // "&amp;lt;" is a literal "&lt;" in the rendered text, not a "<".
        #expect(HTMLCodeBlocks.decodeEntities("&amp;lt;") == "&lt;")
    }

    @Test func `decimal hex and non-ASCII numeric entities decode`() {
        #expect(HTMLCodeBlocks.decodeEntities("&#60;tag&#x3E; &#x1F680; &#955;") == "<tag> 🚀 λ")
    }

    @Test func `invalid numeric entities remain literal`() {
        #expect(HTMLCodeBlocks.decodeEntities("&#xD800; &#1114112; &#nope;") == "&#xD800; &#1114112; &#nope;")
    }

    @Test func `br and block tags inside code become newlines`() {
        let html = "<pre>line one<br>line two</pre>"
        #expect(HTMLCodeBlocks.segments(html) == [.code(languageHint: nil, code: "line one\nline two")])
    }

    @Test func `literal less than signs do not erase code`() {
        #expect(HTMLCodeBlocks.stripTags("if x < y {\nreturn x > 0") == "if x < y {\nreturn x > 0")
        #expect(HTMLCodeBlocks.stripTags("value <unfinished") == "value <unfinished")
        #expect(HTMLCodeBlocks.stripTags("if (a<b && c>d)") == "if (a<b && c>d)")
        #expect(HTMLCodeBlocks.stripTags("Array<String> values") == "Array<String> values")
        #expect(HTMLCodeBlocks.stripTags("<code class=\"swift\">let x = 1</code>") == "let x = 1")
    }

    @Test func `language hint reads from a lang attribute on pre`() {
        let hint = HTMLCodeBlocks.languageHint(openTag: "<pre lang=\"swift\">", inner: "code")
        #expect(hint == "swift")
    }

    @Test func `language hints preserve underscores and dots`() {
        #expect(HTMLCodeBlocks.languageHint(
            openTag: "<pre>",
            inner: "<code class=\"language-objective_c extra\">code</code>"
        ) == "objective_c")
        #expect(HTMLCodeBlocks.languageHint(openTag: "<pre lang=\"node.js\">", inner: "code") == "node.js")
        #expect(CodeLanguage.detect(hint: "objective_c") == .cFamily)
        #expect(CodeLanguage.detect(hint: "node.js") == .javascript)
    }

    @Test func `metadata attributes are not mistaken for lang`() {
        #expect(HTMLCodeBlocks.languageHint(openTag: "<pre data-lang=\"python\">", inner: "code") == nil)
        #expect(HTMLCodeBlocks.languageHint(openTag: "<pre x-lang=\"python\">", inner: "code") == nil)
        #expect(HTMLCodeBlocks.languageHint(
            openTag: "<pre data-lang=\"python\" lang = \"swift\">",
            inner: "code"
        ) == "swift")
    }

    @Test func `an unterminated pre keeps the remainder as prose`() {
        let html = "<p>Intro</p><pre>broken"
        let segments = HTMLCodeBlocks.segments(html)
        #expect(segments == [.prose("<p>Intro</p>"), .prose("<pre>broken")])
    }

    @Test func `tags whose names begin with pre are not code blocks`() {
        let html = "<presentation>slides</presentation><pre>actual code</pre>"
        #expect(HTMLCodeBlocks.segments(html) == [
            .prose("<presentation>slides</presentation>"),
            .code(languageHint: nil, code: "actual code")
        ])
    }
}
