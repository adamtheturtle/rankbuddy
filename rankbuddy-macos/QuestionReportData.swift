//
//  QuestionReportData.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit

nonisolated struct QuestionDetailRequestIdentity: Hashable {
    let accountID: UUID?
    let questionID: String
}

/// A question plus the rich fields currently available in its inspector.
nonisolated struct QuestionReportData {
    let question: Question
    let options: [String]
    let correctAnswer: String?
    let internalNotes: String?

    init(question: Question, detail: QuestionDetail? = nil, includeCorrectAnswer: Bool = false) {
        self.question = question
        options = detail?.options ?? []
        correctAnswer = includeCorrectAnswer
            ? Self.correctAnswerText(from: detail?.answer, options: options)
            : nil
        internalNotes = detail?.internalNotes
    }

    static func correctAnswerText(from answer: QuestionAnswer?, options: [String]) -> String? {
        guard let answer else { return nil }

        let texts = answer.indices.compactMap { index -> String? in
            guard index > 0, index <= options.count else { return nil }

            return options[index - 1]
        }
        return texts.isEmpty ? nil : texts.joined(separator: ", ")
    }

    func optionLabel(at index: Int) -> String {
        let option = options[index]
        return option == correctAnswer ? "\(option) (correct)" : option
    }
}
