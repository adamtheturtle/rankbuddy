//
//  QuestionReportData.swift
//  rankbuddy-macos
//

import HackerRankKit

/// A question plus the rich fields currently available in its inspector.
nonisolated struct QuestionReportData {
    let question: Question
    let options: [String]
    let correctAnswer: String?
    let internalNotes: String?

    init(question: Question, detail: QuestionDetail? = nil, includeCorrectAnswer: Bool = false) {
        self.question = question
        options = detail?.options ?? []
        correctAnswer = includeCorrectAnswer ? detail?.answer : nil
        internalNotes = detail?.internalNotes
    }

    func optionLabel(at index: Int) -> String {
        let option = options[index]
        return option == correctAnswer ? "\(option) (correct)" : option
    }
}
