//
//  QuestionEditValidation.swift
//  rankbuddy-macos
//

import Foundation

nonisolated enum QuestionEditValidation {
    static func maxScore(from text: String) -> Double? {
        guard let value = Double(text), value.isFinite, value >= 0 else { return nil }

        return value
    }
}
