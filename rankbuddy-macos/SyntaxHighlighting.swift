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

/// A run of code of one `TokenKind`. The concatenation of every span's `text`, in order, is
/// exactly the original source — so highlighting never drops or reorders characters.
nonisolated struct SyntaxSpan: Equatable {
    let text: String
    let kind: TokenKind
}

/// A programming language RankBuddy can highlight (#94). Each case carries just enough lexical
/// configuration — keywords and comment styles — for the shared lexer; `plain` highlights only
/// strings, numbers, and comments it can detect generically.
nonisolated enum CodeLanguage: Equatable {
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

    /// Splits `code` into ordered spans. Comments and strings take precedence over keywords and
    /// numbers, so a keyword inside a string or comment is not mis-coloured.
    func spans(_ code: String) -> [SyntaxSpan] {
        let chars = Array(code)
        var spans: [SyntaxSpan] = []
        var plainStart = 0
        var index = 0

        func flushPlain(upTo end: Int) {
            guard end > plainStart else { return }

            spans.append(SyntaxSpan(text: String(chars[plainStart ..< end]), kind: .plain))
        }

        func emit(_ start: Int, _ end: Int, _ kind: TokenKind) {
            flushPlain(upTo: start)
            spans.append(SyntaxSpan(text: String(chars[start ..< end]), kind: kind))
            plainStart = end
        }

        while index < chars.count {
            if let end = lineCommentEnd(chars, from: index) {
                emit(index, end, .comment)
                index = end
            } else if let end = blockCommentEnd(chars, from: index) {
                emit(index, end, .comment)
                index = end
            } else if let end = stringEnd(chars, from: index) {
                emit(index, end, .string)
                index = end
            } else if let end = numberEnd(chars, from: index) {
                emit(index, end, .number)
                index = end
            } else if let end = identifierEnd(chars, from: index) {
                if isKeyword(chars, index, end) {
                    emit(index, end, .keyword)
                }
                index = end
            } else {
                index += 1
            }
        }

        flushPlain(upTo: chars.count)
        return spans
    }

    private func lineCommentEnd(_ chars: [Character], from start: Int) -> Int? {
        for prefix in language.lineCommentPrefixes where matches(chars, start, prefix) {
            var end = start
            while end < chars.count, chars[end] != "\n" {
                end += 1
            }
            return end
        }
        return nil
    }

    private func blockCommentEnd(_ chars: [Character], from start: Int) -> Int? {
        guard language.hasBlockComments, matches(chars, start, "/*") else { return nil }

        var end = start + 2
        while end < chars.count {
            if matches(chars, end, "*/") { return end + 2 }

            end += 1
        }
        return chars.count
    }

    private func stringEnd(_ chars: [Character], from start: Int) -> Int? {
        let delimiters: Set<Character> = ["\"", "'", "`"]
        guard let delimiter = chars[safe: start], delimiters.contains(delimiter) else { return nil }

        var end = start + 1
        while end < chars.count {
            if chars[end] == "\\" {
                end += 2
                continue
            }
            if chars[end] == delimiter { return end + 1 }
            // A bare delimiter that never closes on its line is not a string (e.g. an apostrophe
            // in prose) — bail so it stays plain.
            if chars[end] == "\n" { return nil }

            end += 1
        }
        return nil
    }

    private func numberEnd(_ chars: [Character], from start: Int) -> Int? {
        guard let first = chars[safe: start], first.isNumber else { return nil }

        // A number must not start in the middle of an identifier (e.g. the `2` in `utf8`).
        if let prev = chars[safe: start - 1], prev.isLetter || prev == "_" { return nil }

        var end = start
        while end < chars.count {
            let char = chars[end]
            if char.isHexDigit || char == "." || char == "x" || char == "_" {
                end += 1
            } else {
                break
            }
        }
        return end
    }

    private func identifierEnd(_ chars: [Character], from start: Int) -> Int? {
        guard let first = chars[safe: start], first.isLetter || first == "_" else { return nil }

        var end = start + 1
        while end < chars.count, chars[end].isLetter || chars[end].isNumber || chars[end] == "_" {
            end += 1
        }
        return end
    }

    private func isKeyword(_ chars: [Character], _ start: Int, _ end: Int) -> Bool {
        let word = String(chars[start ..< end])
        if language.keywordsAreCaseInsensitive {
            return language.keywords.contains(word.lowercased())
        }
        return language.keywords.contains(word)
    }

    private func matches(_ chars: [Character], _ start: Int, _ token: String) -> Bool {
        let token = Array(token)
        guard start + token.count <= chars.count else { return false }

        for offset in 0 ..< token.count where chars[start + offset] != token[offset] {
            return false
        }
        return true
    }
}

private extension Array {
    /// Bounds-checked subscript so the lexer can peek past the ends without trapping.
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension SyntaxHighlighter {
    // MARK: Keyword sets

    nonisolated static let swiftKeywords: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "func", "import", "init",
        "inout", "let", "operator", "private", "protocol", "public", "internal", "fileprivate",
        "static", "struct", "subscript", "typealias", "var", "break", "case", "continue",
        "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat",
        "return", "switch", "where", "while", "as", "catch", "false", "is", "nil", "rethrows",
        "super", "self", "throw", "throws", "true", "try", "async", "await", "some", "any"
    ]

    nonisolated static let pythonKeywords: Set<String> = [
        "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del",
        "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in",
        "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while",
        "with", "yield", "True", "False", "None", "self"
    ]

    nonisolated static let javascriptKeywords: Set<String> = [
        "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete",
        "do", "else", "export", "extends", "finally", "for", "function", "if", "import", "in",
        "instanceof", "new", "return", "super", "switch", "this", "throw", "try", "typeof",
        "var", "void", "while", "with", "let", "yield", "async", "await", "static", "true",
        "false", "null", "undefined", "of"
    ]

    nonisolated static let javaKeywords: Set<String> = [
        "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class",
        "const", "continue", "default", "do", "double", "else", "enum", "extends", "final",
        "finally", "float", "for", "if", "implements", "import", "instanceof", "int",
        "interface", "long", "native", "new", "package", "private", "protected", "public",
        "return", "short", "static", "super", "switch", "synchronized", "this", "throw",
        "throws", "transient", "try", "void", "volatile", "while", "true", "false", "null", "var"
    ]

    nonisolated static let cFamilyKeywords: Set<String> = [
        "auto", "bool", "break", "case", "catch", "char", "class", "const", "continue",
        "default", "delete", "do", "double", "else", "enum", "extern", "float", "for",
        "friend", "goto", "if", "inline", "int", "long", "namespace", "new", "operator",
        "private", "protected", "public", "register", "return", "short", "signed", "sizeof",
        "static", "struct", "switch", "template", "this", "throw", "try", "typedef", "typename",
        "union", "unsigned", "using", "virtual", "void", "volatile", "while", "true", "false",
        "nullptr", "string", "vector"
    ]

    nonisolated static let rubyKeywords: Set<String> = [
        "begin", "break", "case", "class", "def", "defined?", "do", "else", "elsif", "end",
        "ensure", "false", "for", "if", "in", "module", "next", "nil", "not", "or", "and",
        "redo", "rescue", "retry", "return", "self", "super", "then", "true", "undef", "unless",
        "until", "when", "while", "yield", "require", "attr_accessor", "puts"
    ]

    nonisolated static let goKeywords: Set<String> = [
        "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough",
        "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range",
        "return", "select", "struct", "switch", "type", "var", "true", "false", "nil", "string",
        "int", "error"
    ]

    nonisolated static let sqlKeywords: Set<String> = [
        "select", "from", "where", "insert", "into", "values", "update", "set", "delete",
        "create", "table", "drop", "alter", "add", "column", "join", "inner", "left", "right",
        "outer", "on", "group", "by", "order", "having", "limit", "offset", "as", "and", "or",
        "not", "null", "is", "in", "like", "between", "distinct", "count", "sum", "avg", "min",
        "max", "primary", "key", "foreign", "references", "index", "view", "union", "all",
        "case", "when", "then", "else", "end"
    ]
}
