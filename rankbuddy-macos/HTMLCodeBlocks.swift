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

        while let preStart = preTagStart(in: rest) {
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

    private static func preTagStart(in html: Substring) -> Range<String.Index>? {
        var searchStart = html.startIndex
        while let match = html.range(
            of: "<pre",
            options: .caseInsensitive,
            range: searchStart ..< html.endIndex
        ) {
            guard match.upperBound < html.endIndex else { return match }

            let boundary = html[match.upperBound]
            if boundary == ">" || boundary == "/" || boundary.isWhitespace {
                return match
            }
            searchStart = match.upperBound
        }
        return nil
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
        var index = html.startIndex
        while index < html.endIndex {
            guard html[index] == "<" else {
                result.append(html[index])
                html.formIndex(after: &index)
                continue
            }

            let contentStart = html.index(after: index)
            guard contentStart < html.endIndex,
                  let close = html[contentStart...].firstIndex(of: ">"),
                  let tag = knownTagName(in: html[contentStart ..< close])
            else {
                result.append("<")
                index = contentStart
                continue
            }

            if tag.hasPrefix("br") || tag == "/div" || tag == "/p" {
                result.append("\n")
            }
            index = html.index(after: close)
        }
        return result
    }

    private static func knownTagName(in content: Substring) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let closing = trimmed.hasPrefix("/")
        let body = closing ? trimmed.dropFirst() : trimmed[...]
        let name = body.prefix(while: \.isLetter).lowercased()
        let known = ["b", "br", "code", "div", "em", "i", "p", "span", "strong"]
        guard known.contains(name) else { return nil }

        let remainder = body.dropFirst(name.count).trimmingCharacters(in: .whitespacesAndNewlines)
        if closing {
            guard remainder.isEmpty else { return nil }

            return "/\(name)"
        }
        guard remainder.isEmpty || remainder == "/" || (remainder.contains("=") && !remainder.contains("&"))
        else { return nil }

        return name
    }

    /// Decodes the HTML entities that appear in escaped source code.
    static func decodeEntities(_ string: String) -> String {
        let named = [
            "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "amp": "&"
        ]
        var result = ""
        var index = string.startIndex
        while index < string.endIndex {
            guard string[index] == "&",
                  let semicolon = string[index...].firstIndex(of: ";")
            else {
                result.append(string[index])
                string.formIndex(after: &index)
                continue
            }

            let bodyStart = string.index(after: index)
            let body = String(string[bodyStart ..< semicolon])
            if let decoded = named[body] ?? numericEntity(body) {
                result.append(contentsOf: decoded)
                index = string.index(after: semicolon)
            } else {
                result.append("&")
                index = bodyStart
            }
        }
        return result
    }

    private static func numericEntity(_ body: String) -> String? {
        guard body.first == "#" else { return nil }

        let digits = body.dropFirst()
        let isHex = digits.first == "x" || digits.first == "X"
        let number = isHex ? digits.dropFirst() : digits[...]
        guard !number.isEmpty,
              let value = UInt32(number, radix: isHex ? 16 : 10),
              let scalar = UnicodeScalar(value)
        else { return nil }

        return String(Character(scalar))
    }
}
