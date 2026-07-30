//
//  QuestionEditValidation.swift
//  rankbuddy-macos
//

import Foundation

nonisolated enum QuestionEditValidation {
    static let recommendedDurationRange = 0 ... 1440

    static func maxScore(from text: String) -> Double? {
        guard let value = Double(text), value.isFinite, value >= 0 else { return nil }

        return value
    }

    static func isValidRecommendedDuration(_ value: Int?) -> Bool {
        value.map(recommendedDurationRange.contains) ?? true
    }
}

nonisolated enum QuestionCreationValidation {
    static func isValidDurationText(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty || Int(normalized).map { $0 >= 0 } == true
    }

    static func duration(from text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func isValidMaxScoreText(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty || Double(normalized) != nil
    }

    static func maxScore(from text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
