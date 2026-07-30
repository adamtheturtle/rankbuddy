//
//  SyntaxKeywords.swift
//  rankbuddy-macos
//

import Foundation

extension SyntaxHighlighter {
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
