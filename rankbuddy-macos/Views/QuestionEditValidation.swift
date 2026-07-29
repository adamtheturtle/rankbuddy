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
