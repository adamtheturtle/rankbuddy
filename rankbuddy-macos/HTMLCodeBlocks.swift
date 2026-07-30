//
//  HTMLCodeBlocks.swift
//  rankbuddy-macos
//

import Foundation

/// Splits an HTML fragment into prose and fenced code segments (#94).
///
/// HackerRank problem statements and test instructions arrive as HTML with code inside
/// `<pre><code class="language-x">…</code></pre>`. The existing `HTMLText` flattens those to
/// plain monospace; this separates the code out so it can be syntax-highlighted while the prose
/// keeps rendering through `HTMLText`. Pure string work, so it is unit-tested directly.
nonisolated enum HTMLCodeBlocks {
    /// One piece of a problem statement: prose HTML (rendered by `HTMLText`) or a code block
    /// (rendered by `CodeBlock`).
    enum Segment: Equatable {
        case prose(String)
        case code(languageHint: String?, code: String)
    }

    /// Splits `html` into ordered segments. When there are no `<pre>` blocks the whole input is
    /// a single `.prose` segment, so callers can use this in place of `HTMLText` everywhere.
    static func segments(_ html: String) -> [Segment] {
        var segments: [Segment] = []
        var rest = Substring(html)

        while let preStart = rest.range(of: "<pre", options: .caseInsensitive) {
            let prose = rest[rest.startIndex ..< preStart.lowerBound]
            if !prose.isEmpty {
                segments.append(.prose(String(prose)))
            }

            guard let openEnd = rest.range(of: ">", range: preStart.lowerBound ..< rest.endIndex),
                  let close = rest.range(
                      of: "</pre>", options: .caseInsensitive, range: openEnd.upperBound ..< rest.endIndex
                  )
            else {
                // Malformed (unterminated <pre>): keep the remainder as prose and stop.
                segments.append(.prose(String(rest[preStart.lowerBound...])))
                return segments
            }

            let openTag = String(rest[preStart.lowerBound ..< openEnd.upperBound])
            let inner = String(rest[openEnd.upperBound ..< close.lowerBound])
            segments.append(.code(
                languageHint: languageHint(openTag: openTag, inner: inner),
                code: decodeEntities(stripTags(inner))
            ))
            rest = rest[close.upperBound...]
        }

        if !rest.isEmpty {
            segments.append(.prose(String(rest)))
        }
        return segments
    }

    /// A language hint pulled from a `language-xxx`/`lang-xxx` class or a `lang="xxx"` attribute
    /// on the `<pre>` tag or the inner `<code>` tag, or `nil` when none is present.
    static func languageHint(openTag: String, inner: String) -> String? {
        let codeTag = inner.range(of: "<code", options: .caseInsensitive).map { range -> String in
            let tail = inner[range.lowerBound...]
            guard let end = tail.range(of: ">") else { return String(tail) }

            return String(tail[..<end.upperBound])
        }
        for source in [openTag, codeTag] {
            if let source, let hint = hint(in: source) {
                return hint
            }
        }
        return nil
    }

    private static func hint(in tag: String) -> String? {
        // `class="language-python"` / `class="lang-py"` / `class="python"`, or `lang="python"`.
        if let marker = tag.range(of: "language-", options: .caseInsensitive)
            ?? tag.range(of: "lang-", options: .caseInsensitive) {
            return token(in: tag, after: marker.upperBound)
        }
        if let attr = tag.range(of: "lang=", options: .caseInsensitive) {
            return quotedValue(in: tag, after: attr.upperBound)
        }
        if let attr = tag.range(of: "class=", options: .caseInsensitive) {
            return quotedValue(in: tag, after: attr.upperBound)
        }
        return nil
    }

    /// Reads one complete HTML attribute/class token starting at `start`.
    private static func token(in string: String, after start: String.Index) -> String? {
        var result = ""
        var index = start
        while index < string.endIndex {
            let char = string[index]
            if char.isWhitespace || char == "\"" || char == "'" || char == ">" {
                break
            }
            result.append(char)
            index = string.index(after: index)
        }
        return result.isEmpty ? nil : result
    }

    /// Reads the value of a quoted attribute, skipping an optional opening quote.
    private static func quotedValue(in string: String, after start: String.Index) -> String? {
        var index = start
        if index < string.endIndex, string[index] == "\"" || string[index] == "'" {
            index = string.index(after: index)
        }
        return token(in: string, after: index)
    }

    /// Removes HTML tags, turning `<br>` and `</…>` line breaks into newlines so the code keeps
    /// its line structure.
    static func stripTags(_ html: String) -> String {
        var result = ""
        var insideTag = false
        var tagBuffer = ""

        for char in html {
            if char == "<" {
                insideTag = true
                tagBuffer = ""
            } else if char == ">" {
                insideTag = false
                let tag = tagBuffer.lowercased()
                if tag.hasPrefix("br") || tag == "/div" || tag == "/p" {
                    result.append("\n")
                }
            } else if insideTag {
                tagBuffer.append(char)
            } else {
                result.append(char)
            }
        }
        return result
    }

    /// Decodes the HTML entities that appear in escaped source code.
    static func decodeEntities(_ string: String) -> String {
        var result = string
        let replacements = [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "), ("&#x27;", "'"), ("&#x2F;", "/"), ("&#47;", "/"), ("&amp;", "&")
        ]
        for (entity, character) in replacements {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }
}
