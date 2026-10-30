//
//  QuestionEditValidation.swift
//  rankbuddy-macos
//

import Foundation

nonisolated enum QuestionEditValidation {
    static let maxSystemPromptLength = 15000

    static func systemPromptIssue(_ prompt: String) -> String? {
        prompt.unicodeScalars.count > maxSystemPromptLength
            ? "Custom system prompt must be at most 15,000 characters." : nil
    }

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
    static let maxNameLength = 255

    static func nameIssue(_ name: String) -> String? {
        name.count > maxNameLength ? "Question name can be at most 255 characters." : nil
    }

    static func isValidDurationText(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty || Int(normalized).map { $0 >= 0 } == true
    }

    static func duration(from text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func isValidMaxScoreText(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty || Double(normalized).map { $0.isFinite && $0 >= 0 } == true
    }

    static func maxScore(from text: String) -> Double? {
        let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        return value.map { $0.isFinite && $0 >= 0 } == true ? value : nil
    }
}
