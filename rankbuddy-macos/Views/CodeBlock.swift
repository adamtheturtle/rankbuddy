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
    var showsPlaceholder = true
    @State private var segmentedHTML: String?
    @State private var segments: [HTMLCodeBlocks.Segment]?

    private var displayedSegments: [HTMLCodeBlocks.Segment]? {
        if segmentedHTML == html, let segments {
            return segments
        }
        return HTMLCodeBlockSegmentCache.segments(for: html)
    }

    var body: some View {
        Group {
            if let displayedSegments {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(displayedSegments.enumerated()), id: \.offset) { _, segment in
                        switch segment {
                        case let .prose(prose):
                            HTMLFragmentText(html: prose, showsPlaceholder: false)
                        case let .code(hint, code):
                            CodeBlock(code: code, languageHint: hint)
                        }
                    }
                }
            } else if showsPlaceholder, !html.isEmpty {
                Text("Loading…")
                    .foregroundStyle(.secondary)
            } else {
                // A real (zero-size) view, not EmptyView, so `.task` below always fires.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .task(id: html) { await prepareSegments() }
    }

    @MainActor
    private func prepareSegments() async {
        if let cached = HTMLCodeBlockSegmentCache.segments(for: html) {
            segmentedHTML = html
            segments = cached
            return
        }

        segmentedHTML = nil
        segments = nil
        await Task.yield()
        guard !Task.isCancelled else { return }

        let prepared = HTMLCodeBlocks.segments(html)
        guard !Task.isCancelled else { return }

        HTMLCodeBlockSegmentCache.store(prepared, for: html)
        segmentedHTML = html
        segments = prepared
    }
}

@MainActor
private enum HTMLCodeBlockSegmentCache {
    private static let capacity = 80
    private static var values: [String: [HTMLCodeBlocks.Segment]] = [:]
    private static var keys: [String] = []

    static func segments(for html: String) -> [HTMLCodeBlocks.Segment]? {
        values[html]
    }

    static func store(_ segments: [HTMLCodeBlocks.Segment], for html: String) {
        guard values[html] == nil else { return }

        values[html] = segments
        keys.append(html)
        if keys.count > capacity {
            values[keys.removeFirst()] = nil
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
