//
//  CodeBlock.swift
//  rankbuddy-macos
//

import SwiftUI

/// The colour palette for syntax tokens (#94). Uses semantic SwiftUI colours that already adapt
/// to light and dark mode, so the same theme reads well in both.
enum CodeTheme {
    static func color(for kind: TokenKind) -> Color {
        switch kind {
        case .plain: .primary
        case .keyword: .pink
        case .string: .green
        case .comment: .secondary
        case .number: .blue
        }
    }

    /// Builds a monospaced `AttributedString` for the highlighted code.
    static func attributed(_ code: String, language: CodeLanguage) -> AttributedString {
        let spans = SyntaxHighlighter(language: language).spans(code)
        var result = AttributedString()
        for span in spans {
            var piece = AttributedString(span.text)
            piece.foregroundColor = color(for: span.kind)
            result.append(piece)
        }
        result.font = .system(.body, design: .monospaced)
        return result
    }
}

/// Renders a syntax-highlighted, horizontally scrollable code block with a subtle card
/// background (#94). Read-only; reused for both problem-statement code and (later) submitted
/// code.
struct CodeBlock: View {
    let code: String
    let language: CodeLanguage

    init(code: String, languageHint: String?) {
        self.code = code
        language = CodeLanguage.detect(hint: languageHint)
    }

    init(code: String, language: CodeLanguage) {
        self.code = code
        self.language = language
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(CodeTheme.attributed(code, language: language))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topTrailing) {
            if let label = languageLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .accessibilityHidden(true)
            }
        }
    }

    /// A short uppercased language tag shown in the corner, or `nil` for unrecognised code.
    private var languageLabel: String? {
        switch language {
        case .swift: "SWIFT"
        case .python: "PYTHON"
        case .javascript: "JS"
        case .java: "JAVA"
        case .cFamily: "C/C++"
        case .ruby: "RUBY"
        case .golang: "GO"
        case .sql: "SQL"
        case .plain: nil
        }
    }
}

/// Renders an HTML problem statement or instructions, syntax-highlighting any `<pre>` code
/// blocks while keeping the surrounding prose on the existing `HTMLText` path (#94/#35). Drop-in
/// replacement for `HTMLText` for the rich text fields.
struct HighlightedHTMLText: View {
    let html: String

    var body: some View {
        let segments = HTMLCodeBlocks.segments(html)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case let .prose(prose):
                    HTMLText(html: prose)
                case let .code(hint, code):
                    CodeBlock(code: code, languageHint: hint)
                }
            }
        }
    }
}

#Preview("Highlighted statement") {
    Form {
        Section("Problem statement") {
            HighlightedHTMLText(html: #"""
            <p>Write a function that returns the <b>sum</b> of a list.</p>
            <pre><code class="language-python">def total(values):
                # add them up
                result = 0
                for v in values:
                    result += v
                return result  # done
            </code></pre>
            <p>Constraints: <code>1 &lt;= n &lt;= 100</code>.</p>
            """#)
        }
    }
    .formStyle(.grouped)
    .frame(width: 460, height: 420)
}

#Preview("Code block (Swift)") {
    CodeBlock(code: """
    func greet(_ name: String) -> String {
        // build a greeting
        let count = 42
        return "Hello, \\(name)!"
    }
    """, language: .swift)
        .padding()
        .frame(width: 420)
}
