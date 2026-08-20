//
//  QuestionDetailView+EditingRows.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

struct QuestionEditOverlay {
    private(set) var name: String?
    private(set) var options = QuestionWriteOptions()

    mutating func merge(name: String?, options update: QuestionWriteOptions) {
        self.name = name ?? self.name
        options = QuestionWriteOptions(
            languages: update.languages ?? options.languages,
            problemStatement: update.problemStatement ?? options.problemStatement,
            recommendedDuration: update.clearsRecommendedDuration
                ? nil : update.recommendedDuration ?? options.recommendedDuration,
            internalNotes: update.internalNotes ?? options.internalNotes,
            tags: update.tags ?? options.tags,
            mcqOptions: update.mcqOptions ?? options.mcqOptions,
            answer: update.answer ?? options.answer,
            clearsRecommendedDuration: update.recommendedDuration == nil
                ? update.clearsRecommendedDuration || options.clearsRecommendedDuration : false
        )
    }

    func applying(to question: Question) -> Question {
        question.applying(name: name, options)
    }
}

extension QuestionDetailView {
    /// Per-field editable rows: each saves immediately and reverts if the write fails.
    @ViewBuilder var editableRows: some View {
        EditableNumberRow(label: "Recommended duration (minutes)", value: displayed.recommendedDuration) { newValue in
            guard QuestionEditValidation.isValidRecommendedDuration(newValue) else {
                editError = "Recommended duration must be between 0 and 1,440 minutes."
                return false
            }

            return await save(QuestionWriteOptions(
                recommendedDuration: newValue,
                clearsRecommendedDuration: newValue == nil
            ))
        }
        EditableLanguagesRow(value: displayed.languages) { newValue in
            await save(QuestionWriteOptions(languages: newValue ?? []))
        }
        EditableTextRow(
            label: "Tags",
            value: displayed.tags?.joined(separator: ", ") ?? "",
            prompt: "Comma-separated"
        ) { newValue in
            await save(QuestionWriteOptions(tags: splitList(newValue) ?? []))
        }
    }
}

extension Question {
    /// A copy with a successful update's fields folded in, so the detail can display the
    /// saved state without a full list refresh (the write echo is only id/name/type).
    func applying(name: String?, _ options: QuestionWriteOptions) -> Question {
        Question(
            id: id,
            uniqueID: uniqueID,
            type: type,
            name: name ?? self.name,
            owner: owner,
            createdAt: createdAt,
            status: status,
            languages: options.languages ?? languages,
            problemStatement: options.problemStatement ?? problemStatement,
            recommendedDuration: options.clearsRecommendedDuration
                ? nil : options.recommendedDuration ?? recommendedDuration,
            tags: options.tags ?? tags,
            maxScore: maxScore,
            skills: skills
        )
    }
}
