//
//  SyntaxHighlightingTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

struct SyntaxHighlightingTests {
    /// The lexer must never alter the source: concatenating every span reproduces the input.
    private func assertLossless(_ code: String, _ language: CodeLanguage) {
        let highlighter = SyntaxHighlighter(language: language)
        let spans = highlighter.spans(code)
        #expect(spans.map(\.text).joined() == code)
        #expect(highlighter.tokens(code).map { String(code[$0.range]) }.joined() == code)
    }

    private func kinds(_ code: String, _ language: CodeLanguage) -> [TokenKind] {
        SyntaxHighlighter(language: language).spans(code).map(\.kind)
    }

    private func text(_ code: String, _ language: CodeLanguage, of kind: TokenKind) -> [String] {
        SyntaxHighlighter(language: language).spans(code).filter { $0.kind == kind }.map(\.text)
    }

    @Test func `language detection maps common hints`() {
        #expect(CodeLanguage.detect(hint: "py") == .python)
        #expect(CodeLanguage.detect(hint: "JavaScript") == .javascript)
        #expect(CodeLanguage.detect(hint: "c++") == .cFamily)
        #expect(CodeLanguage.detect(hint: "golang") == .golang)
        #expect(CodeLanguage.detect(hint: "mysql") == .sql)
        #expect(CodeLanguage.detect(hint: nil) == .plain)
        #expect(CodeLanguage.detect(hint: "brainfuck") == .plain)
    }

    @Test func `highlighting is lossless across languages`() {
        assertLossless("def f(x):\n  return x # comment", .python)
        assertLossless("let x = \"hi\" // note", .swift)
        assertLossless("SELECT * FROM t WHERE id = 1", .sql)
        assertLossless("", .plain)
    }

    @Test func `keywords, strings, numbers, and comments are classified`() {
        let code = "let total = 42 // sum"
        #expect(text(code, .swift, of: .keyword) == ["let"])
        #expect(text(code, .swift, of: .number) == ["42"])
        #expect(text(code, .swift, of: .comment) == ["// sum"])
    }

    @Test func `a keyword inside a string is not highlighted`() {
        let spans = SyntaxHighlighter(language: .swift).spans("let s = \"return now\"")
        let stringSpans = spans.filter { $0.kind == .string }
        #expect(stringSpans.map(\.text) == ["\"return now\""])
        // "return" only appears inside the string, so it is never a keyword span.
        #expect(!spans.contains { $0.kind == .keyword && $0.text == "return" })
    }

    @Test func `swift raw string matches its hash delimiter`() {
        let raw = "##\"a quote \\\" and // text\"##"
        #expect(text(raw, .swift, of: .string) == [raw])
        #expect(text(raw, .swift, of: .comment).isEmpty)
    }

    @Test func `swift and python triple quoted strings span lines`() {
        let swift = "\"\"\"first\nreturn // text\nlast\"\"\""
        let python = "'''first\nreturn # text\nlast'''"
        let rawSwift = "#\"\"\"first\n\"quoted\" // text\nlast\"\"\"#"
        #expect(text(swift, .swift, of: .string) == [swift])
        #expect(text(python, .python, of: .string) == [python])
        #expect(text(rawSwift, .swift, of: .string) == [rawSwift])
    }

    @Test func `c sharp interpolated and verbatim strings protect their contents`() {
        let code = #"$"value {item} // text" @"quote "" and /* text */" $@"{item} // text""#
        #expect(text(code, .cFamily, of: .string) == [
            #"$"value {item} // text""#,
            #"@"quote "" and /* text */""#,
            #"$@"{item} // text""#
        ])
        #expect(text(code, .cFamily, of: .comment).isEmpty)
    }

    @Test func `javascript template interpolation stays in the string token`() {
        let template = #"`value ${item ?? "// text"}`"#
        #expect(text(template, .javascript, of: .string) == [template])
        #expect(text(template, .javascript, of: .comment).isEmpty)
    }

    @Test func `block comments span multiple lines for c-family`() {
        let code = "int x; /* a\nb */ y"
        #expect(text(code, .cFamily, of: .comment) == ["/* a\nb */"])
    }

    @Test func `swift block comments preserve nested comments`() {
        let code = "let before = 1 /* outer /* inner */ return \"text\" */ let after = 2"
        #expect(text(code, .swift, of: .comment) == ["/* outer /* inner */ return \"text\" */"])
        #expect(text(code, .swift, of: .keyword) == ["let", "let"])
    }

    @Test func `sql keywords match case-insensitively`() {
        #expect(text("select From", .sql, of: .keyword).count == 2)
        // Python is case-sensitive, so "Return" is not a keyword.
        #expect(text("Return", .python, of: .keyword).isEmpty)
    }

    @Test func `a digit inside an identifier is not a number`() {
        #expect(text("utf8 encode", .swift, of: .number).isEmpty)
    }

    @Test func `scientific notation includes a signed exponent`() {
        #expect(text("1e+10 6.02e-23 2E3", .swift, of: .number) == ["1e+10", "6.02e-23", "2E3"])
    }

    @Test func `decimal numbers do not consume or precede identifier letters`() {
        #expect(text("123abc 42value", .swift, of: .number).isEmpty)
        #expect(text("123.45 0x1A_F", .swift, of: .number) == ["123.45", "0x1A_F"])
    }
}
