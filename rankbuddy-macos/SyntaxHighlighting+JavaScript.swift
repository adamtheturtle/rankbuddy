//
//  SyntaxHighlighting+JavaScript.swift
//  rankbuddy-macos
//

import Foundation

extension SyntaxHighlighter {
    // Template interpolation is a small nested lexer: braces can nest, and quoted strings,
    // comments, or nested templates inside an expression must not close the outer template.
    // swiftlint:disable:next cyclomatic_complexity
    nonisolated func javascriptTemplateEnd(_ code: String, from start: String.Index) -> String.Index? {
        var end = code.index(after: start)
        var interpolationDepth = 0
        while end < code.endIndex {
            if code[end] == "\\" {
                code.formIndex(after: &end)
                if end < code.endIndex {
                    code.formIndex(after: &end)
                }
                continue
            }
            if code[end...].hasPrefix("${") {
                interpolationDepth += 1
                end = code.index(end, offsetBy: 2)
                continue
            }
            if interpolationDepth == 0, code[end] == "`" {
                return code.index(after: end)
            }
            if interpolationDepth > 0 {
                if code[end] == "`", let nestedEnd = javascriptTemplateEnd(code, from: end) {
                    end = nestedEnd
                    continue
                }
                if let commentEnd = lineCommentEnd(code, from: end) ?? blockCommentEnd(code, from: end) {
                    end = commentEnd
                    continue
                }
                if code[end] == "\"" || code[end] == "'",
                   let quotedEnd = stringEnd(code, from: end) {
                    end = quotedEnd
                    continue
                }
                if code[end] == "{" {
                    interpolationDepth += 1
                } else if code[end] == "}" {
                    interpolationDepth -= 1
                }
            }
            code.formIndex(after: &end)
        }
        return nil
    }
}
