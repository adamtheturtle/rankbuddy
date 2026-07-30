//
//  SyntaxHighlighting.swift
//  rankbuddy-macos
//

import SwiftUI

/// The kind of token a syntax span represents, mapped to a colour by the theme (#94).
nonisolated enum TokenKind: Equatable {
    case plain
    case keyword
    case string
    case comment
    case number
}

/// A token range into its source string. The lexer uses ranges so the rendering path does not
/// allocate a separate `String` for every highlighted and plain run.
nonisolated struct SyntaxToken {
    let range: Range<String.Index>
    let kind: TokenKind
}

/// A run of code of one `TokenKind`. The concatenation of every span's `text`, in order, is
/// exactly the original source — so highlighting never drops or reorders characters.
nonisolated struct SyntaxSpan: Equatable {
    let text: String
    let kind: TokenKind
}

/// A programming language RankBuddy can highlight (#94). Each case carries just enough lexical
/// configuration — keywords and comment styles — for the shared lexer; `plain` highlights only
/// strings, numbers, and comments it can detect generically.
nonisolated enum CodeLanguage: Hashable {
    case swift
    case python
    case javascript
    case java
    case cFamily
    case ruby
    case golang
    case sql
    case plain

    /// Maps a free-text hint (an HTML `language-xxx` class, a file extension, or a HackerRank
    /// language code) to a language, defaulting to `.plain` when unrecognised.
    static func detect(hint: String?) -> Self {
        guard let hint = hint?.lowercased().trimmingCharacters(in: .whitespaces), !hint.isEmpty else {
            return .plain
        }

        switch hint {
        case "swift": return .swift
        case "python", "python3", "py", "py3": return .python
        case "javascript", "js", "node", "nodejs", "typescript", "ts": return .javascript
        case "java": return .java
        case "c", "cpp", "c++", "cplusplus", "objc", "objective-c", "csharp", "c#", "cs": return .cFamily
        case "ruby", "rb": return .ruby
        case "go", "golang": return .golang
        case "sql", "mysql", "postgres", "postgresql", "tsql", "plsql": return .sql
        default: return .plain
        }
    }

    /// Keywords highlighted for this language. A shared C-family/Java/JS/Swift core plus the
    /// per-language additions; kept deliberately small — enough to read as "highlighted code".
    var keywords: Set<String> {
        switch self {
        case .swift:
            SyntaxHighlighter.swiftKeywords
        case .python:
            SyntaxHighlighter.pythonKeywords
        case .javascript:
            SyntaxHighlighter.javascriptKeywords
        case .java:
            SyntaxHighlighter.javaKeywords
        case .cFamily:
            SyntaxHighlighter.cFamilyKeywords
        case .ruby:
            SyntaxHighlighter.rubyKeywords
        case .golang:
            SyntaxHighlighter.goKeywords
        case .sql:
            SyntaxHighlighter.sqlKeywords
        case .plain:
            []
        }
    }

    /// The prefixes that start a line comment (to end of line).
    var lineCommentPrefixes: [String] {
        switch self {
        case .python, .ruby: ["#"]
        case .sql: ["--", "#"]
        case .plain: ["//", "#"]
        default: ["//"]
        }
    }

    /// Whether `/* … */` block comments are recognised.
    var hasBlockComments: Bool {
        switch self {
        case .python, .ruby: false
        default: true
        }
    }

    /// SQL keywords are conventionally matched case-insensitively; most languages are not.
    var keywordsAreCaseInsensitive: Bool {
        self == .sql
    }
}

/// A lightweight, dependency-free syntax highlighter (#94): a single configurable lexer that
/// splits source into `SyntaxSpan`s of keywords, strings, comments, and numbers. Not a full
/// parser — it is line/character based and language-agnostic enough to read well across the
/// languages HackerRank problems use, while never altering the underlying text.
nonisolated struct SyntaxHighlighter {
    let language: CodeLanguage

    private enum StringEscape {
        case backslash
        case doubledQuote
        case literal
    }

    private struct StringRule {
        let prefix: String
        let terminator: String
        let escape: StringEscape
        let allowsNewline: Bool
    }

    /// Splits `code` into ordered spans. Comments and strings take precedence over keywords and
    /// numbers, so a keyword inside a string or comment is not mis-coloured.
    func spans(_ code: String) -> [SyntaxSpan] {
        tokens(code).map { SyntaxSpan(text: String(code[$0.range]), kind: $0.kind) }
    }

    /// Splits `code` into source ranges without materialising an array of characters or copying
    /// each run. Renderers can apply attributes directly to these ranges.
    func tokens(_ code: String) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        var plainStart = code.startIndex
        var index = code.startIndex

        func flushPlain(upTo end: String.Index) {
            guard end > plainStart else { return }

            tokens.append(SyntaxToken(range: plainStart ..< end, kind: .plain))
        }

        func emit(_ start: String.Index, _ end: String.Index, _ kind: TokenKind) {
            flushPlain(upTo: start)
            tokens.append(SyntaxToken(range: start ..< end, kind: kind))
            plainStart = end
        }

        while index < code.endIndex {
            if let end = lineCommentEnd(code, from: index) {
                emit(index, end, .comment)
                index = end
            } else if let end = blockCommentEnd(code, from: index) {
                emit(index, end, .comment)
                index = end
            } else if let end = stringEnd(code, from: index) {
                emit(index, end, .string)
                index = end
            } else if let end = numberEnd(code, from: index) {
                emit(index, end, .number)
                index = end
            } else if let end = identifierEnd(code, from: index) {
                if isKeyword(code, index, end) {
                    emit(index, end, .keyword)
                }
                index = end
            } else {
                code.formIndex(after: &index)
            }
        }

        flushPlain(upTo: code.endIndex)
        return tokens
    }

    private func lineCommentEnd(_ code: String, from start: String.Index) -> String.Index? {
        for prefix in language.lineCommentPrefixes where code[start...].hasPrefix(prefix) {
            var end = start
            while end < code.endIndex, code[end] != "\n" {
                code.formIndex(after: &end)
            }
            return end
        }
        return nil
    }

    private func blockCommentEnd(_ code: String, from start: String.Index) -> String.Index? {
        guard language.hasBlockComments, code[start...].hasPrefix("/*") else { return nil }

        var end = code.index(start, offsetBy: 2)
        while end < code.endIndex {
            if code[end...].hasPrefix("*/") {
                return code.index(end, offsetBy: 2)
            }
            code.formIndex(after: &end)
        }
        return code.endIndex
    }

    private func stringEnd(_ code: String, from start: String.Index) -> String.Index? {
        guard let rule = stringRule(code, from: start) else { return nil }

        var end = code.index(start, offsetBy: rule.prefix.count)
        while end < code.endIndex {
            if rule.escape == .backslash, code[end] == "\\" {
                code.formIndex(after: &end)
                if end < code.endIndex {
                    code.formIndex(after: &end)
                }
                continue
            }
            if rule.escape == .doubledQuote, code[end...].hasPrefix("\"\"") {
                end = code.index(end, offsetBy: 2)
                continue
            }
            if code[end...].hasPrefix(rule.terminator) {
                return code.index(end, offsetBy: rule.terminator.count)
            }
            // A bare delimiter that never closes on its line is not a string (e.g. an apostrophe
            // in prose) — bail so it stays plain.
            if !rule.allowsNewline, code[end] == "\n" { return nil }

            code.formIndex(after: &end)
        }
        return nil
    }

    private func stringRule(_ code: String, from start: String.Index) -> StringRule? {
        if language == .swift {
            var quote = start
            while quote < code.endIndex, code[quote] == "#" {
                code.formIndex(after: &quote)
            }
            if quote > start, quote < code.endIndex, code[quote] == "\"" {
                let hashes = String(code[start ..< quote])
                return StringRule(
                    prefix: hashes + "\"",
                    terminator: "\"" + hashes,
                    escape: .literal,
                    allowsNewline: false
                )
            }
        }

        if language == .cFamily {
            for prefix in ["$@\"", "@$\"", "@\"", "$\""] where code[start...].hasPrefix(prefix) {
                return StringRule(
                    prefix: prefix,
                    terminator: "\"",
                    escape: prefix.contains("@") ? .doubledQuote : .backslash,
                    allowsNewline: prefix.contains("@")
                )
            }
        }

        let delimiter = code[start]
        guard ["\"", "'", "`"].contains(delimiter) else { return nil }

        return StringRule(
            prefix: String(delimiter),
            terminator: String(delimiter),
            escape: .backslash,
            allowsNewline: false
        )
    }

    private func numberEnd(_ code: String, from start: String.Index) -> String.Index? {
        guard code[start].isNumber else { return nil }

        // A number must not start in the middle of an identifier (e.g. the `2` in `utf8`).
        if start > code.startIndex {
            let previous = code[code.index(before: start)]
            if previous.isLetter || previous == "_" { return nil }
        }

        var end = code.index(after: start)
        if code[start] == "0", end < code.endIndex, code[end] == "x" || code[end] == "X" {
            return hexadecimalEnd(code, afterPrefix: code.index(after: end))
        }

        while end < code.endIndex, code[end].isNumber || code[end] == "_" {
            code.formIndex(after: &end)
        }
        if end < code.endIndex, code[end] == "." {
            code.formIndex(after: &end)
            while end < code.endIndex, code[end].isNumber || code[end] == "_" {
                code.formIndex(after: &end)
            }
        }
        if end < code.endIndex,
           code[end] == "e" || code[end] == "E",
           let exponentEnd = exponentEnd(code, marker: end) {
            end = exponentEnd
        }
        guard !continuesIdentifier(code, at: end) else { return nil }

        return end
    }

    private func hexadecimalEnd(_ code: String, afterPrefix start: String.Index) -> String.Index? {
        var end = start
        var hasDigit = false
        while end < code.endIndex, code[end].isHexDigit || code[end] == "_" {
            hasDigit = hasDigit || code[end].isHexDigit
            code.formIndex(after: &end)
        }
        guard hasDigit, !continuesIdentifier(code, at: end) else { return nil }

        return end
    }

    private func continuesIdentifier(_ code: String, at index: String.Index) -> Bool {
        guard index < code.endIndex else { return false }

        return code[index].isLetter || code[index].isNumber || code[index] == "_"
    }

    private func exponentEnd(_ code: String, marker: String.Index) -> String.Index? {
        var end = code.index(after: marker)
        if end < code.endIndex, code[end] == "+" || code[end] == "-" {
            code.formIndex(after: &end)
        }

        var hasDigit = false
        while end < code.endIndex, code[end].isNumber || code[end] == "_" {
            hasDigit = hasDigit || code[end].isNumber
            code.formIndex(after: &end)
        }
        return hasDigit ? end : nil
    }

    private func identifierEnd(_ code: String, from start: String.Index) -> String.Index? {
        let first = code[start]
        guard first.isLetter || first == "_" else { return nil }

        var end = code.index(after: start)
        while end < code.endIndex, code[end].isLetter || code[end].isNumber || code[end] == "_" {
            code.formIndex(after: &end)
        }
        return end
    }

    private func isKeyword(_ code: String, _ start: String.Index, _ end: String.Index) -> Bool {
        let word = String(code[start ..< end])
        if language.keywordsAreCaseInsensitive {
            return language.keywords.contains(word.lowercased())
        }
        return language.keywords.contains(word)
    }
}
