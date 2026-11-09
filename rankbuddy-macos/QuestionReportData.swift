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

/// The intended reader determines whether confidential question fields belong in the document.
nonisolated enum QuestionDocumentAudience {
    case candidate
    case interviewer
}

/// Shared, audience-filtered data for both Markdown and printable question documents.
nonisolated struct QuestionReportData {
    let question: Question
    let options: [String]
    let correctAnswer: String?
    let internalNotes: String?

    init(question: Question, detail: QuestionDetail? = nil, audience: QuestionDocumentAudience = .candidate) {
        self.question = audience == .interviewer ? question : Question(
            id: question.id, type: question.type, name: question.name,
            languages: question.languages, problemStatement: question.problemStatement,
            recommendedDuration: question.recommendedDuration, maxScore: question.maxScore
        )
        options = detail?.options ?? []
        correctAnswer = audience == .interviewer
            ? Self.correctAnswerText(from: detail?.answer, options: options)
            : nil
        internalNotes = audience == .interviewer ? detail?.internalNotes : nil
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
