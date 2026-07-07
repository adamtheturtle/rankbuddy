//
//  HTMLText.swift
//  rankbuddy-macos
//

import AppKit
import SwiftUI

/// Renders an HTML fragment as formatted, selectable text.
///
/// HackerRank returns some text fields — a test's `instructions`, a question's
/// `problem_statement` — as HTML (#35). Shown verbatim they leak raw `<p>`/`<b>`/`<ul>`
/// markup, so this converts the HTML to an `AttributedString`, normalising the importer's
/// hard-coded fonts and colours so the text adopts the app's body font and adapts to
/// light/dark mode, while preserving bold/italic/monospace emphasis from the source.
struct HTMLText: View {
    let html: String

    var body: some View {
        Text(AttributedString.fromHTML(html))
            .textSelection(.enabled)
    }
}

/// Renders HTML fragments with first-class layout for ordered lists.
struct HTMLFragmentText: View {
    let html: String

    var body: some View {
        let segments = HTMLFragmentSegment.segments(from: html)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case let .prose(prose):
                    if !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HTMLText(html: prose)
                    }
                case let .orderedList(items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(index + 1).")
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .trailing)

                                HTMLText(html: item)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private enum HTMLFragmentSegment {
    case prose(String)
    case orderedList([String])

    static func segments(from html: String) -> [HTMLFragmentSegment] {
        let listPattern = #"(?is)<ol\b[^>]*>(.*?)</ol>"#
        guard let listExpression = try? NSRegularExpression(pattern: listPattern) else {
            return [.prose(html)]
        }

        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        var segments: [HTMLFragmentSegment] = []
        var cursor = 0

        for match in listExpression.matches(in: html, range: fullRange) {
            if match.range.location > cursor {
                segments.append(.prose(nsHTML.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }

            let listHTML = nsHTML.substring(with: match.range(at: 1))
            let items = orderedListItems(from: listHTML)
            if items.isEmpty {
                segments.append(.prose(nsHTML.substring(with: match.range)))
            } else {
                segments.append(.orderedList(items))
            }

            cursor = match.range.location + match.range.length
        }

        if cursor < nsHTML.length {
            segments.append(.prose(nsHTML.substring(from: cursor)))
        }

        return segments.isEmpty ? [.prose(html)] : segments
    }

    private static func orderedListItems(from html: String) -> [String] {
        let itemPattern = #"(?is)<li\b[^>]*>(.*?)</li>"#
        guard let itemExpression = try? NSRegularExpression(pattern: itemPattern) else { return [] }

        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        return itemExpression.matches(in: html, range: fullRange).map { match in
            nsHTML.substring(with: match.range(at: 1))
        }
    }
}

extension AttributedString {
    /// Builds an `AttributedString` from an HTML fragment, normalised for in-app display.
    ///
    /// Falls back to a plain-text attributed string of `html` if it cannot be parsed as
    /// HTML, so the user always sees the content (just without formatting).
    ///
    /// `@MainActor` because AppKit's HTML importer is only safe to use on the main thread.
    @MainActor static func fromHTML(_ html: String) -> AttributedString {
        guard let data = html.data(using: .utf8),
              let parsed = try? NSAttributedString(
                  data: data,
                  options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue
                  ],
                  documentAttributes: nil
              )
        else {
            return AttributedString(html)
        }

        var result = AttributedString(normalised(parsed))
        // The HTML importer appends a trailing newline after block elements; drop it so the
        // text doesn't render with a dangling blank line inside its Form section.
        while result.characters.last == "\n" {
            let last = result.index(result.endIndex, offsetByCharacters: -1)
            result.removeSubrange(last ..< result.endIndex)
        }
        return result
    }

    /// Replaces the importer's hard-coded fonts with the system body font (preserving
    /// bold/italic/monospace traits) and removes explicit colours, so the text inherits the
    /// app's appearance and adapts to light/dark mode.
    private static func normalised(_ attributed: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: result.length)
        let body = NSFont.preferredFont(forTextStyle: .body)

        result.enumerateAttribute(.font, in: full) { value, range, _ in
            let traits = (value as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            let kept = traits.intersection([.bold, .italic, .monoSpace])
            let descriptor = body.fontDescriptor.withSymbolicTraits(kept)
            let font = NSFont(descriptor: descriptor, size: body.pointSize) ?? body
            result.addAttribute(.font, value: font, range: range)
        }
        result.removeAttribute(.foregroundColor, range: full)
        return result
    }
}

#Preview {
    Form {
        Section("Instructions") {
            HTMLText(html: """
            <p>Solve <b>all</b> questions within the <i>time limit</i>. You may use:</p>
            <ul><li>The standard library</li><li>One scratch file</li></ul>
            <p>Inputs &amp; outputs are validated. See <code>main()</code> for the entry point.</p>
            """)
        }
    }
    .formStyle(.grouped)
    .frame(width: 420, height: 320)
}
