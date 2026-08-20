//
//  QuestionDetailView+Panes.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

extension QuestionDetailView {
    @ViewBuilder var selectedPaneContent: some View {
        switch selectedPane {
        case .overview:
            Section("Properties") {
                OptionalRow("Unique ID", displayed.uniqueID)
                OptionalRow("Created", DisplayFormat.date(displayed.createdAt))
                if canEdit {
                    editableRows
                } else {
                    OptionalRow("Max score", displayed.maxScore.map { $0.formatted() })
                    OptionalRow("Recommended duration", displayed.recommendedDuration.map { "\($0) minutes" })
                    OptionalRow("Languages", DisplayFormat.languages(displayed.languages))
                    OptionalRow("Skills", DisplayFormat.list(displayed.skills))
                }
            }

            if !canEdit, let tags = displayed.tags, !tags.isEmpty {
                Section("Tags") {
                    TagList(tags: tags)
                }
            }

        case .content:
            problemStatementSection
            if let notes = detail?.internalNotes, !notes.isEmpty {
                Section("Internal notes") {
                    HTMLText(html: notes)
                }
            }

        case .answer:
            if let detail, !detail.options.isEmpty {
                Section("Options") {
                    ForEach(Array(detail.options.enumerated()), id: \.offset) { index, option in
                        let optionText = MarkdownExport.plainText(fromHTML: option)
                        Label {
                            HTMLText(html: option)
                        } icon: {
                            Image(systemName: isCorrect(option) ? "checkmark.circle.fill" : "circle")
                        }
                        .foregroundStyle(isCorrect(option) ? Color.green : Color.primary)
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityLabel(isCorrect(option) ? "\(optionText), correct answer" : optionText)
                        .id(index)
                    }
                }
            }

            if let answerText = QuestionReportData.correctAnswerText(
                from: detail?.answer,
                options: detail?.options ?? []
            ), !answerText.isEmpty {
                Section("Answer") {
                    if answerRevealed {
                        Text(answerText).textSelection(.enabled)
                    } else {
                        Button {
                            answerRevealed = true
                        } label: {
                            Label("Reveal answer", systemImage: "eye")
                        }
                        .help("Show the correct answer")
                    }
                }
            }

            if detail?.options.isEmpty != false,
               QuestionReportData.correctAnswerText(from: detail?.answer, options: detail?.options ?? []) == nil {
                ContentUnavailableView(
                    "No Answer Available",
                    systemImage: "checkmark.seal",
                    description: Text("HackerRank did not return answer details for this question.")
                )
            }

        case .coding:
            codingSection
        }
    }

    @ViewBuilder private var problemStatementSection: some View {
        if canEdit {
            Section("Problem statement") {
                // Edits work on the raw source; display renders HackerRank's HTML.
                InlineEditableText(
                    text: problemStatement ?? "",
                    placeholder: "Add a problem statement",
                    rendersHTML: true
                ) { newValue in
                    await save(QuestionWriteOptions(problemStatement: newValue))
                }
            }
        } else if let statement = problemStatement {
            Section("Problem statement") {
                HighlightedHTMLText(html: statement)
            }
        } else {
            ContentUnavailableView(
                "No Content Available",
                systemImage: "text.alignleft",
                description: Text("This question does not have a problem statement.")
            )
        }
    }
}
