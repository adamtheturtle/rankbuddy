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
        if let classValue = attribute(named: "class", in: tag) {
            let classes = classValue.split(whereSeparator: \.isWhitespace).map(String.init)
            for className in classes {
                if className.lowercased().hasPrefix("language-") {
                    return String(className.dropFirst("language-".count))
                }
                if className.lowercased().hasPrefix("lang-") {
                    return String(className.dropFirst("lang-".count))
                }
            }
            if let lang = attribute(named: "lang", in: tag) {
                return lang
            }
            return classes.first
        }
        return attribute(named: "lang", in: tag)
    }

    /// Reads an attribute only when `name` is its complete name, not a suffix such as
    /// `data-lang`.
    private static func attribute(named name: String, in tag: String) -> String? {
        var searchStart = tag.startIndex
        while let match = tag.range(
            of: name,
            options: [.caseInsensitive],
            range: searchStart ..< tag.endIndex
        ) {
            searchStart = match.upperBound
            let hasLeadingBoundary = match.lowerBound == tag.startIndex
                || tag[tag.index(before: match.lowerBound)].isWhitespace
                || tag[tag.index(before: match.lowerBound)] == "<"
            guard hasLeadingBoundary else { continue }

            var index = match.upperBound
            while index < tag.endIndex, tag[index].isWhitespace {
                tag.formIndex(after: &index)
            }
            guard index < tag.endIndex, tag[index] == "=" else { continue }

            tag.formIndex(after: &index)
            while index < tag.endIndex, tag[index].isWhitespace {
                tag.formIndex(after: &index)
            }
            guard index < tag.endIndex else { return nil }

            let quote: Character? = tag[index] == "\"" || tag[index] == "'" ? tag[index] : nil
            if quote != nil {
                tag.formIndex(after: &index)
            }
            let valueStart = index
            while index < tag.endIndex {
                if let quote, tag[index] == quote {
                    break
                }
                if quote == nil, tag[index].isWhitespace || tag[index] == ">" {
                    break
                }
                tag.formIndex(after: &index)
            }
            let value = String(tag[valueStart ..< index])
            return value.isEmpty ? nil : value
        }
        return nil
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
