//
//  QuestionDetailView+EditingRows.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

struct QuestionEditOverlay {
    private(set) var changes = QuestionMetadataChanges()

    mutating func merge(_ update: QuestionMetadataChanges) {
        changes = QuestionMetadataChanges(
            name: update.name ?? changes.name,
            type: update.type ?? changes.type,
            internalNotes: update.internalNotes ?? changes.internalNotes,
            languages: update.languages ?? changes.languages,
            problemStatement: update.problemStatement ?? changes.problemStatement,
            recommendedDuration: update.recommendedDuration ?? changes.recommendedDuration,
            tags: update.tags ?? changes.tags,
            options: update.options ?? changes.options,
            answer: update.answer ?? changes.answer,
            customSystemPrompt: update.customSystemPrompt ?? changes.customSystemPrompt
        )
    }

    func applying(to question: Question) -> Question {
        question.applying(changes)
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

            return await save(QuestionMetadataChanges(
                recommendedDuration: newValue
            ))
        }
        EditableLanguagesRow(value: displayed.languages) { newValue in
            await save(QuestionMetadataChanges(languages: newValue ?? []))
        }
        EditableTextRow(
            label: "Tags",
            value: displayed.tags?.joined(separator: ", ") ?? "",
            prompt: "Comma-separated"
        ) { newValue in
            await save(QuestionMetadataChanges(tags: splitList(newValue) ?? []))
        }
    }
}

extension Question {
    /// A copy with a successful update's fields folded in, so the detail can display the
    /// saved state without a full list refresh (the write echo is only id/name/type).
    func applying(_ changes: QuestionMetadataChanges) -> Question {
        Question(
            id: id,
            uniqueID: uniqueID,
            type: changes.type ?? type,
            name: changes.name ?? name,
            owner: owner,
            createdAt: createdAt,
            status: status,
            languages: changes.languages ?? languages,
            problemStatement: changes.problemStatement ?? problemStatement,
            recommendedDuration: changes.recommendedDuration ?? recommendedDuration,
            tags: changes.tags ?? tags,
            maxScore: maxScore,
            skills: skills,
            customSystemPrompt: changes.customSystemPrompt ?? customSystemPrompt
        )
    }
}
